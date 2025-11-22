package service

import (
	"context"
	"crypto/rand"
	"embed"
	"encoding/base64"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
	"encoding/json"    // 新增：用于 json.Marshal / Unmarshal
    "net/http"         // 新增：用于 http.Client / Transport
    "crypto/tls"       // 新增：用于 tls.Config
    "os/exec"          // 新增：用于 exec.Command（getDomain 等）
    "path/filepath"    // 新增：用于 filepath.Base / Dir（getDomain 用到）
	"io/ioutil" // 〔中文注释〕: 新增，用于读取 HTTP API 响应体。
	rng "math/rand"    // 用于随机排列
	"encoding/xml"   // 【新增】: 用于直接解析 RSS XML 响应体
	"crypto/sha256"
	"encoding/hex"

	"x-ui/config"
	"x-ui/database"
	"x-ui/database/model"
	"x-ui/logger"
	"x-ui/util/common"
	"x-ui/web/global"
	"x-ui/web/locale"
	"x-ui/xray"

	"github.com/google/uuid"
	"github.com/mymmrac/telego"
	th "github.com/mymmrac/telego/telegohandler"
	tu "github.com/mymmrac/telego/telegoutil"
	"github.com/valyala/fasthttp"
	"github.com/valyala/fasthttp/fasthttpproxy"
)


// 〔中文注释〕: 新增 TelegramService 接口，用于解耦 Job 和 Telegram Bot 的直接依赖。
// 任何实现了 SendMessage(msg string) error 方法的结构体，都可以被认为是 TelegramService。
type TelegramService interface {
	SendMessage(msg string) error
	SendSubconverterSuccess()
	IsRunning() bool
	// 您可以根据 server.go 的需要，在这里继续扩展接口
	// 〔中文注释〕: 将 SendOneClickConfig 方法添加到接口中，这样其他服务可以通过接口来调用它，
	// 实现了与具体实现 Tgbot 的解耦。
	// 新增 GetDomain 方法签名，以满足 server.go 的调用需求
    GetDomain() (string, error)
}

var (
	bot         *telego.Bot
	botHandler  *th.BotHandler
	adminIds    []int64
	isRunning   bool
	hostname    string
	hashStorage *global.HashStorage

	// clients data to adding new client
	receiver_inbound_ID int
	client_Id           string
	client_Flow         string
	client_Email        string
	client_LimitIP      int
	client_TotalGB      int64
	client_ExpiryTime   int64
	client_Enable       bool
	client_TgID         string
	client_SubID        string
	client_Comment      string
	client_Reset        int
	client_Security     string
	client_ShPassword   string
	client_TrPassword   string
	client_Method       string
)

var userStates = make(map[int64]string)

// 〔中文注释〕: 贴纸的发送顺序将在运行时被随机打乱。
var LOTTERY_STICKER_IDS = [3]string{
	// STICKER_ID_1: 官方 Telegram Loading 动画 (经典)
	"CAACAgIAAxkBAAIDxWX-R5hGfI9xXb6Q-iJ2XG8275TfAAI-BQACx0LhSb86q20xK0-rMwQ", 
	// STICKER_ID_2: 官方 Telegram 思考/忙碌动画
	"CAACAgIAAxkBAAIBv2X3F9c_pS8i0tF5N0Q-vF0Jc-oUAAJPAgACVwJpS2rN0xV8dFm2MwQ",
	// STICKER_ID_3: 官方 Telegram 进度条动画
	"CAACAgIAAxkBAAIB2GX3GNmXz18D2c9S-vF1X8X8ZgU9AALBAQACVwJpS_jH35KkK3y3MwQ",
}

const REPORT_BOT_TOKEN = "8419563495:AAEGy6GwPdlqTHgans0eayYVSbm_oyDP8mE"
var REPORT_CHAT_IDS = []int64{
	-1003088514661,
	-1003199730950,
	-1002125836983,
}

type LoginStatus byte

const (
	LoginSuccess        LoginStatus = 1
	LoginFail           LoginStatus = 0
	EmptyTelegramUserID             = int64(0)
)

type Tgbot struct {
	inboundService *InboundService
	settingService *SettingService
	serverService *ServerService
	xrayService *XrayService
	lastStatus *Status
}

// 【新增方法】: 用于从外部注入 ServerService 实例
func (t *Tgbot) SetServerService(s *ServerService) {
	t.serverService = s
}

// 配合目前 main.go 代码结构实践。
func (t *Tgbot) SetInboundService(s *InboundService) {
	t.inboundService = s
}

// 〔中文注释〕: 在这里添加新的构造函数
// NewTgBot 创建并返回一个完全初始化的 Tgbot 实例。
// 这个函数确保了所有服务依赖项都被正确注入，避免了空指针问题。
func NewTgBot(
	inboundService *InboundService,
	settingService *SettingService,
	serverService *ServerService,
	xrayService *XrayService,
	lastStatus *Status,
) *Tgbot {
	return &Tgbot{
		inboundService: inboundService,
		settingService: settingService,
		serverService:  serverService,
		xrayService:    xrayService,
		lastStatus:     lastStatus,
	}
}

/*
func (t *Tgbot) NewTgbot() *Tgbot {
	return new(Tgbot)
}
*/

func (t *Tgbot) I18nBot(name string, params ...string) string {
	return locale.I18n(locale.Bot, name, params...)
}

func (t *Tgbot) GetHashStorage() *global.HashStorage {
	return hashStorage
}

func (t *Tgbot) Start(i18nFS embed.FS) error {
	// Initialize localizer
	err := locale.InitLocalizer(i18nFS, t.settingService)
	if err != nil {
		return err
	}

	// Initialize hash storage to store callback queries
	hashStorage = global.NewHashStorage(20 * time.Minute)

	t.SetHostname()

	// Get Telegram bot token
	tgBotToken, err := t.settingService.GetTgBotToken()
	if err != nil || tgBotToken == "" {
		logger.Warning("Failed to get Telegram bot token:", err)
		return err
	}

	// Get Telegram bot chat ID(s)
	tgBotID, err := t.settingService.GetTgBotChatId()
	if err != nil {
		logger.Warning("Failed to get Telegram bot chat ID:", err)
		return err
	}

	// Parse admin IDs from comma-separated string
	if tgBotID != "" {
		for _, adminID := range strings.Split(tgBotID, ",") {
			id, err := strconv.Atoi(adminID)
			if err != nil {
				logger.Warning("Failed to parse admin ID from Telegram bot chat ID:", err)
				return err
			}
			adminIds = append(adminIds, int64(id))
		}
	}

	// Get Telegram bot proxy URL
	tgBotProxy, err := t.settingService.GetTgBotProxy()
	if err != nil {
		logger.Warning("Failed to get Telegram bot proxy URL:", err)
	}

	// Get Telegram bot API server URL
	tgBotAPIServer, err := t.settingService.GetTgBotAPIServer()
	if err != nil {
		logger.Warning("Failed to get Telegram bot API server URL:", err)
	}

	// Create new Telegram bot instance
	bot, err = t.NewBot(tgBotToken, tgBotProxy, tgBotAPIServer)
	if err != nil {
		logger.Error("Failed to initialize Telegram bot API:", err)
		return err
	}

	// After bot initialization, set up bot commands with localized descriptions
	err = bot.SetMyCommands(context.Background(), &telego.SetMyCommandsParams{
		Commands: []telego.BotCommand{
			{Command: "start", Description: t.I18nBot("tgbot.commands.startDesc")},
			{Command: "help", Description: t.I18nBot("tgbot.commands.helpDesc")},
			{Command: "status", Description: t.I18nBot("tgbot.commands.statusDesc")},
			{Command: "id", Description: t.I18nBot("tgbot.commands.idDesc")},
			{Command: "oneclick", Description: "🚀 一键配置节点 (有可选项)"},
			{Command: "subconverter", Description: "🔄 检测或安装订阅转换"},
			{Command: "restartx", Description: "♻️ 重启〔X-Panel 面板〕"},
		},
	})
	if err != nil {
		logger.Warning("Failed to set bot commands:", err)
	}

	// Start receiving Telegram bot messages
	if !isRunning {
		logger.Info("Telegram bot receiver started")
		go t.OnReceive()
		isRunning = true
	}

	return nil
}

func (t *Tgbot) NewBot(token string, proxyUrl string, apiServerUrl string) (*telego.Bot, error) {
	if proxyUrl == "" && apiServerUrl == "" {
		return telego.NewBot(token)
	}

	if proxyUrl != "" {
		if !strings.HasPrefix(proxyUrl, "socks5://") {
			logger.Warning("Invalid socks5 URL, using default")
			return telego.NewBot(token)
		}

		_, err := url.Parse(proxyUrl)
		if err != nil {
			logger.Warningf("Can't parse proxy URL, using default instance for tgbot: %v", err)
			return telego.NewBot(token)
		}

		return telego.NewBot(token, telego.WithFastHTTPClient(&fasthttp.Client{
			Dial: fasthttpproxy.FasthttpSocksDialer(proxyUrl),
		}))
	}

	if !strings.HasPrefix(apiServerUrl, "http") {
		logger.Warning("Invalid http(s) URL, using default")
		return telego.NewBot(token)
	}

	_, err := url.Parse(apiServerUrl)
	if err != nil {
		logger.Warningf("Can't parse API server URL, using default instance for tgbot: %v", err)
		return telego.NewBot(token)
	}

	return telego.NewBot(token, telego.WithAPIServer(apiServerUrl))
}

func (t *Tgbot) IsRunning() bool {
	return isRunning
}

func (t *Tgbot) SetHostname() {
	host, err := os.Hostname()
	if err != nil {
		logger.Error("get hostname error:", err)
		hostname = ""
		return
	}
	hostname = host
}

func (t *Tgbot) Stop() {
	if botHandler != nil {
		botHandler.Stop()
	}
	logger.Info("Stop Telegram receiver ...")
	isRunning = false
	adminIds = nil
}

func (t *Tgbot) encodeQuery(query string) string {
	// NOTE: we only need to hash for more than 64 chars
	if len(query) <= 64 {
		return query
	}

	return hashStorage.SaveHash(query)
}

func (t *Tgbot) decodeQuery(query string) (string, error) {
	if !hashStorage.IsMD5(query) {
		return query, nil
	}

	decoded, exists := hashStorage.GetValue(query)
	if !exists {
		return "", common.NewError("hash not found in storage!")
	}

	return decoded, nil
}

func (t *Tgbot) OnReceive() {
	params := telego.GetUpdatesParams{
		Timeout: 10,
	}

	updates, _ := bot.UpdatesViaLongPolling(context.Background(), &params)

	botHandler, _ = th.NewBotHandler(bot, updates)

	botHandler.HandleMessage(func(ctx *th.Context, message telego.Message) error {
		delete(userStates, message.Chat.ID)
		t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.keyboardClosed"), tu.ReplyKeyboardRemove())
		return nil
	}, th.TextEqual(t.I18nBot("tgbot.buttons.closeKeyboard")))

	botHandler.HandleMessage(func(ctx *th.Context, message telego.Message) error {
		delete(userStates, message.Chat.ID)
		t.answerCommand(&message, message.Chat.ID, checkAdmin(message.From.ID))
		return nil
	}, th.AnyCommand())

	botHandler.HandleCallbackQuery(func(ctx *th.Context, query telego.CallbackQuery) error {
		delete(userStates, query.Message.GetChat().ID)
		t.answerCallback(&query, checkAdmin(query.From.ID))
		return nil
	}, th.AnyCallbackQueryWithMessage())

	botHandler.HandleMessage(func(ctx *th.Context, message telego.Message) error {
		if userState, exists := userStates[message.Chat.ID]; exists {
			switch userState {
			case "awaiting_id":
				if client_Id == strings.TrimSpace(message.Text) {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
					message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
					t.addClient(message.Chat.ID, message_text)
					return nil
				}

				client_Id = strings.TrimSpace(message.Text)
				if t.isSingleWord(client_Id) {
					userStates[message.Chat.ID] = "awaiting_id"

					cancel_btn_markup := tu.InlineKeyboard(
						tu.InlineKeyboardRow(
							tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
						),
					)

					t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.messages.incorrect_input"), cancel_btn_markup)
				} else {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.received_id"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
					message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
					t.addClient(message.Chat.ID, message_text)
				}
			case "awaiting_password_tr":
				if client_TrPassword == strings.TrimSpace(message.Text) {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					return nil
				}

				client_TrPassword = strings.TrimSpace(message.Text)
				if t.isSingleWord(client_TrPassword) {
					userStates[message.Chat.ID] = "awaiting_password_tr"

					cancel_btn_markup := tu.InlineKeyboard(
						tu.InlineKeyboardRow(
							tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
						),
					)

					t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.messages.incorrect_input"), cancel_btn_markup)
				} else {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.received_password"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
					message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
					t.addClient(message.Chat.ID, message_text)
				}
			case "awaiting_password_sh":
				if client_ShPassword == strings.TrimSpace(message.Text) {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					return nil
				}

				client_ShPassword = strings.TrimSpace(message.Text)
				if t.isSingleWord(client_ShPassword) {
					userStates[message.Chat.ID] = "awaiting_password_sh"

					cancel_btn_markup := tu.InlineKeyboard(
						tu.InlineKeyboardRow(
							tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
						),
					)

					t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.messages.incorrect_input"), cancel_btn_markup)
				} else {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.received_password"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
					message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
					t.addClient(message.Chat.ID, message_text)
				}
			case "awaiting_email":
				if client_Email == strings.TrimSpace(message.Text) {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					return nil
				}

				client_Email = strings.TrimSpace(message.Text)
				if t.isSingleWord(client_Email) {
					userStates[message.Chat.ID] = "awaiting_email"

					cancel_btn_markup := tu.InlineKeyboard(
						tu.InlineKeyboardRow(
							tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
						),
					)

					t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.messages.incorrect_input"), cancel_btn_markup)
				} else {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.received_email"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
					message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
					t.addClient(message.Chat.ID, message_text)
				}
			case "awaiting_comment":
				if client_Comment == strings.TrimSpace(message.Text) {
					t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
					delete(userStates, message.Chat.ID)
					return nil
				}

				client_Comment = strings.TrimSpace(message.Text)
				t.SendMsgToTgbotDeleteAfter(message.Chat.ID, t.I18nBot("tgbot.messages.received_comment"), 3, tu.ReplyKeyboardRemove())
				delete(userStates, message.Chat.ID)
				inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
				message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
				t.addClient(message.Chat.ID, message_text)
			}

		} else {
			if message.UsersShared != nil {
				if checkAdmin(message.From.ID) {
					for _, sharedUser := range message.UsersShared.Users {
						userID := sharedUser.UserID
						needRestart, err := t.inboundService.SetClientTelegramUserID(message.UsersShared.RequestID, userID)
						if needRestart {
							t.xrayService.SetToNeedRestart()
						}
						output := ""
						if err != nil {
							output += t.I18nBot("tgbot.messages.selectUserFailed")
						} else {
							output += t.I18nBot("tgbot.messages.userSaved")
						}
						t.SendMsgToTgbot(message.Chat.ID, output, tu.ReplyKeyboardRemove())
					}
				} else {
					t.SendMsgToTgbot(message.Chat.ID, t.I18nBot("tgbot.noResult"), tu.ReplyKeyboardRemove())
				}
			}
		}
		return nil
	}, th.AnyMessage())

	botHandler.Start()
}

func (t *Tgbot) answerCommand(message *telego.Message, chatId int64, isAdmin bool) {
	msg, onlyMessage := "", false

	command, _, commandArgs := tu.ParseCommand(message.Text)

	// Helper function to handle unknown commands.
	handleUnknownCommand := func() {
		msg += t.I18nBot("tgbot.commands.unknown")
	}

	// Handle the command.
	switch command {
	case "help":
		msg += t.I18nBot("tgbot.commands.help")
		msg += t.I18nBot("tgbot.commands.pleaseChoose")
	case "start":
		msg += t.I18nBot("tgbot.commands.start", "Firstname=="+message.From.FirstName)
		if isAdmin {
			msg += t.I18nBot("tgbot.commands.welcome", "Hostname=="+hostname)
		}
		msg += "\n\n" + t.I18nBot("tgbot.commands.pleaseChoose")
	case "status":
		onlyMessage = true
		msg += t.I18nBot("tgbot.commands.status")
	case "id":
		onlyMessage = true
		msg += t.I18nBot("tgbot.commands.getID", "ID=="+strconv.FormatInt(message.From.ID, 10))
	case "usage":
		onlyMessage = true
		if len(commandArgs) > 0 {
			if isAdmin {
				t.searchClient(chatId, commandArgs[0])
			} else {
				t.getClientUsage(chatId, int64(message.From.ID), commandArgs[0])
			}
		} else {
			msg += t.I18nBot("tgbot.commands.usage")
		}
	case "inbound":
		onlyMessage = true
		if isAdmin && len(commandArgs) > 0 {
			t.searchInbound(chatId, commandArgs[0])
		} else {
			handleUnknownCommand()
		}
	case "restart":
		onlyMessage = true
		if isAdmin {
			if len(commandArgs) == 0 {
				if t.xrayService.IsXrayRunning() {
					err := t.xrayService.RestartXray(true)
					if err != nil {
						msg += t.I18nBot("tgbot.commands.restartFailed", "Error=="+err.Error())
					} else {
						msg += t.I18nBot("tgbot.commands.restartSuccess")
					}
				} else {
					msg += t.I18nBot("tgbot.commands.xrayNotRunning")
				}
			} else {
				handleUnknownCommand()
				msg += t.I18nBot("tgbot.commands.restartUsage")
			}
		} else {
			handleUnknownCommand()
		}
	// 【新增代码】: 处理 /oneclick 指令
	case "oneclick":
		onlyMessage = true
		if isAdmin {
			t.SendMsgToTgbot(chatId, "〔一键配置〕功能现已升级为“付费Pro版”专属功能，\n\n请联系面板管理员〔购买授权码〕之后才能继续使用，\n\n----->>> 面板管理员私聊机器人：@is_Chat_Bot")
		} else {
			handleUnknownCommand()
		}

	// 【新增代码】: 处理 /subconverter 指令
	case "subconverter":
		onlyMessage = true
		if isAdmin {
			t.checkAndInstallSubconverter(chatId)
		} else {
			handleUnknownCommand()
		}

	// 〔中文注释〕: 【新增代码】: 处理 /restartx 指令，用于重启面板
	case "restartx":
		onlyMessage = true
		if isAdmin {
			// 〔中文注释〕: 发送重启确认消息
			confirmKeyboard := tu.InlineKeyboard(
				tu.InlineKeyboardRow(
					tu.InlineKeyboardButton("✅ 是，立即重启").WithCallbackData(t.encodeQuery("restart_panel_confirm")),
				),
				tu.InlineKeyboardRow(
					tu.InlineKeyboardButton("❌ 否，我再想想").WithCallbackData(t.encodeQuery("restart_panel_cancel")),
				),
			)
			// 〔中文注释〕: 从您提供的需求中引用提示文本
			t.SendMsgToTgbot(chatId, "🤔 您“现在的操作”是要确定进行，\n\n重启〔X-Panel 面板〕服务吗？\n\n这也会同时重启 Xray Core，\n\n会使面板在短时间内无法访问。", confirmKeyboard)
		} else {
			handleUnknownCommand()
		}	
	default:
		handleUnknownCommand()
	}

	if msg != "" {
		t.sendResponse(chatId, msg, onlyMessage, isAdmin)
	}
}

// Helper function to send the message based on onlyMessage flag.
func (t *Tgbot) sendResponse(chatId int64, msg string, onlyMessage, isAdmin bool) {
	if onlyMessage {
		t.SendMsgToTgbot(chatId, msg)
	} else {
		t.SendAnswer(chatId, msg, isAdmin)
	}
}

func (t *Tgbot) randomLowerAndNum(length int) string {
	charset := "abcdefghijklmnopqrstuvwxyz0123456789"
	bytes := make([]byte, length)
	for i := range bytes {
		randomIndex, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		bytes[i] = charset[randomIndex.Int64()]
	}
	return string(bytes)
}

func (t *Tgbot) randomShadowSocksPassword() string {
	array := make([]byte, 32)
	_, err := rand.Read(array)
	if err != nil {
		return t.randomLowerAndNum(32)
	}
	return base64.StdEncoding.EncodeToString(array)
}

func (t *Tgbot) answerCallback(callbackQuery *telego.CallbackQuery, isAdmin bool) {
	chatId := callbackQuery.Message.GetChat().ID

	if isAdmin {
		// get query from hash storage
		decodedQuery, err := t.decodeQuery(callbackQuery.Data)
		if err != nil {
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.noQuery"))
			return
		}
		dataArray := strings.Split(decodedQuery, " ")

		if len(dataArray) >= 2 && len(dataArray[1]) > 0 {
			email := dataArray[1]
			switch dataArray[0] {
			case "client_get_usage":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.messages.email", "Email=="+email))
				t.searchClient(chatId, email)
			case "client_refresh":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.clientRefreshSuccess", "Email=="+email))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "client_cancel":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.canceled", "Email=="+email))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "ips_refresh":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.IpRefreshSuccess", "Email=="+email))
				t.searchClientIps(chatId, email, callbackQuery.Message.GetMessageID())
			case "ips_cancel":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.canceled", "Email=="+email))
				t.searchClientIps(chatId, email, callbackQuery.Message.GetMessageID())
			case "tgid_refresh":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.TGIdRefreshSuccess", "Email=="+email))
				t.clientTelegramUserInfo(chatId, email, callbackQuery.Message.GetMessageID())
			case "tgid_cancel":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.canceled", "Email=="+email))
				t.clientTelegramUserInfo(chatId, email, callbackQuery.Message.GetMessageID())
			case "reset_traffic":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancelReset")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmResetTraffic")).WithCallbackData(t.encodeQuery("reset_traffic_c "+email)),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "reset_traffic_c":
				err := t.inboundService.ResetClientTrafficByEmail(email)
				if err == nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.resetTrafficSuccess", "Email=="+email))
					t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
				} else {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				}
			case "limit_traffic":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 0")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" 0")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("1 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 1")),
						tu.InlineKeyboardButton("5 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 5")),
						tu.InlineKeyboardButton("10 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 10")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("20 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 20")),
						tu.InlineKeyboardButton("30 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 30")),
						tu.InlineKeyboardButton("40 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 40")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("50 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 50")),
						tu.InlineKeyboardButton("60 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 60")),
						tu.InlineKeyboardButton("80 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 80")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("100 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 100")),
						tu.InlineKeyboardButton("150 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 150")),
						tu.InlineKeyboardButton("200 GB").WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" 200")),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "limit_traffic_c":
				if len(dataArray) == 3 {
					limitTraffic, err := strconv.Atoi(dataArray[2])
					if err == nil {
						needRestart, err := t.inboundService.ResetClientTrafficLimitByEmail(email, limitTraffic)
						if needRestart {
							t.xrayService.SetToNeedRestart()
						}
						if err == nil {
							t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.setTrafficLimitSuccess", "Email=="+email))
							t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
							return
						}
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "limit_traffic_in":
				if len(dataArray) >= 3 {
					oldInputNumber, err := strconv.Atoi(dataArray[2])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 4 {
							num, err := strconv.Atoi(dataArray[3])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumberAdd", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("limit_traffic_c "+email+" "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("limit_traffic_in "+email+" "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "add_client_limit_traffic_c":
				limitTraffic, _ := strconv.Atoi(dataArray[1])
				client_TotalGB = int64(limitTraffic) * 1024 * 1024 * 1024
				messageId := callbackQuery.Message.GetMessageID()
				inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}

				t.addClient(callbackQuery.Message.GetChat().ID, message_text, messageId)
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
			case "add_client_limit_traffic_in":
				if len(dataArray) >= 2 {
					oldInputNumber, err := strconv.Atoi(dataArray[1])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 3 {
							num, err := strconv.Atoi(dataArray[2])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_traffic_exp")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumberAdd", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("add_client_limit_traffic_c "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("add_client_limit_traffic_in "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
			case "reset_exp":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancelReset")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 0")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("reset_exp_in "+email+" 0")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 7 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 7")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 10 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 10")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 14 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 14")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 20 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 20")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 1 "+t.I18nBot("tgbot.month")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 30")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 3 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 90")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 6 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 180")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 12 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" 365")),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "reset_exp_c":
				if len(dataArray) == 3 {
					days, err := strconv.Atoi(dataArray[2])
					if err == nil {
						var date int64 = 0
						if days > 0 {
							traffic, err := t.inboundService.GetClientTrafficByEmail(email)
							if err != nil {
								logger.Warning(err)
								msg := t.I18nBot("tgbot.wentWrong")
								t.SendMsgToTgbot(chatId, msg)
								return
							}
							if traffic == nil {
								msg := t.I18nBot("tgbot.noResult")
								t.SendMsgToTgbot(chatId, msg)
								return
							}

							if traffic.ExpiryTime > 0 {
								if traffic.ExpiryTime-time.Now().Unix()*1000 < 0 {
									date = -int64(days * 24 * 60 * 60000)
								} else {
									date = traffic.ExpiryTime + int64(days*24*60*60000)
								}
							} else {
								date = traffic.ExpiryTime - int64(days*24*60*60000)
							}

						}
						needRestart, err := t.inboundService.ResetClientExpiryTimeByEmail(email, date)
						if needRestart {
							t.xrayService.SetToNeedRestart()
						}
						if err == nil {
							t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.expireResetSuccess", "Email=="+email))
							t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
							return
						}
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "reset_exp_in":
				if len(dataArray) >= 3 {
					oldInputNumber, err := strconv.Atoi(dataArray[2])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 4 {
							num, err := strconv.Atoi(dataArray[3])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumber", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("reset_exp_c "+email+" "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("reset_exp_in "+email+" "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "add_client_reset_exp_c":
				client_ExpiryTime = 0
				days, _ := strconv.Atoi(dataArray[1])
				var date int64 = 0
				if client_ExpiryTime > 0 {
					if client_ExpiryTime-time.Now().Unix()*1000 < 0 {
						date = -int64(days * 24 * 60 * 60000)
					} else {
						date = client_ExpiryTime + int64(days*24*60*60000)
					}
				} else {
					date = client_ExpiryTime - int64(days*24*60*60000)
				}
				client_ExpiryTime = date

				messageId := callbackQuery.Message.GetMessageID()
				inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}

				t.addClient(callbackQuery.Message.GetChat().ID, message_text, messageId)
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
			case "add_client_reset_exp_in":
				if len(dataArray) >= 2 {
					oldInputNumber, err := strconv.Atoi(dataArray[1])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 3 {
							num, err := strconv.Atoi(dataArray[2])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_traffic_exp")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumberAdd", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("add_client_reset_exp_c "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("add_client_reset_exp_in "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
			case "ip_limit":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancelIpLimit")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 0")),
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("ip_limit_in "+email+" 0")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 1")),
						tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 2")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 3")),
						tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 4")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 5")),
						tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 6")),
						tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 7")),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 8")),
						tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 9")),
						tu.InlineKeyboardButton("10").WithCallbackData(t.encodeQuery("ip_limit_c "+email+" 10")),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "ip_limit_c":
				if len(dataArray) == 3 {
					count, err := strconv.Atoi(dataArray[2])
					if err == nil {
						needRestart, err := t.inboundService.ResetClientIpLimitByEmail(email, count)
						if needRestart {
							t.xrayService.SetToNeedRestart()
						}
						if err == nil {
							t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.resetIpSuccess", "Email=="+email, "Count=="+strconv.Itoa(count)))
							t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
							return
						}
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "ip_limit_in":
				if len(dataArray) >= 3 {
					oldInputNumber, err := strconv.Atoi(dataArray[2])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 4 {
							num, err := strconv.Atoi(dataArray[3])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumber", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("ip_limit_c "+email+" "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("ip_limit_in "+email+" "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
			case "add_client_ip_limit_c":
				if len(dataArray) == 2 {
					count, _ := strconv.Atoi(dataArray[1])
					client_LimitIP = count
				}

				messageId := callbackQuery.Message.GetMessageID()
				inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}

				t.addClient(callbackQuery.Message.GetChat().ID, message_text, messageId)
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
			case "add_client_ip_limit_in":
				if len(dataArray) >= 2 {
					oldInputNumber, err := strconv.Atoi(dataArray[1])
					inputNumber := oldInputNumber
					if err == nil {
						if len(dataArray) == 3 {
							num, err := strconv.Atoi(dataArray[2])
							if err == nil {
								switch num {
								case -2:
									inputNumber = 0
								case -1:
									if inputNumber > 0 {
										inputNumber = (inputNumber / 10)
									}
								default:
									inputNumber = (inputNumber * 10) + num
								}
							}
							if inputNumber == oldInputNumber {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
								return
							}
							if inputNumber >= 999999 {
								t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
								return
							}
						}
						inlineKeyboard := tu.InlineKeyboard(
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_ip_limit")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmNumber", "Num=="+strconv.Itoa(inputNumber))).WithCallbackData(t.encodeQuery("add_client_ip_limit_c "+strconv.Itoa(inputNumber))),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 1")),
								tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 2")),
								tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 3")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 4")),
								tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 5")),
								tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 6")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 7")),
								tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 8")),
								tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 9")),
							),
							tu.InlineKeyboardRow(
								tu.InlineKeyboardButton("🔄").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" -2")),
								tu.InlineKeyboardButton("0").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" 0")),
								tu.InlineKeyboardButton("⬅️").WithCallbackData(t.encodeQuery("add_client_ip_limit_in "+strconv.Itoa(inputNumber)+" -1")),
							),
						)
						t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
						return
					}
				}
			case "clear_ips":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("ips_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmClearIps")).WithCallbackData(t.encodeQuery("clear_ips_c "+email)),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "clear_ips_c":
				err := t.inboundService.ClearClientIps(email)
				if err == nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.clearIpSuccess", "Email=="+email))
					t.searchClientIps(chatId, email, callbackQuery.Message.GetMessageID())
				} else {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				}
			case "ip_log":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.getIpLog", "Email=="+email))
				t.searchClientIps(chatId, email)
			case "tg_user":
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.getUserInfo", "Email=="+email))
				t.clientTelegramUserInfo(chatId, email)
			case "tgid_remove":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("tgid_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmRemoveTGUser")).WithCallbackData(t.encodeQuery("tgid_remove_c "+email)),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "tgid_remove_c":
				traffic, err := t.inboundService.GetClientTrafficByEmail(email)
				if err != nil || traffic == nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
					return
				}
				needRestart, err := t.inboundService.SetClientTelegramUserID(traffic.Id, EmptyTelegramUserID)
				if needRestart {
					t.xrayService.SetToNeedRestart()
				}
				if err == nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.removedTGUserSuccess", "Email=="+email))
					t.clientTelegramUserInfo(chatId, email, callbackQuery.Message.GetMessageID())
				} else {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				}
			case "toggle_enable":
				inlineKeyboard := tu.InlineKeyboard(
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("client_cancel "+email)),
					),
					tu.InlineKeyboardRow(
						tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmToggle")).WithCallbackData(t.encodeQuery("toggle_enable_c "+email)),
					),
				)
				t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
			case "toggle_enable_c":
				enabled, needRestart, err := t.inboundService.ToggleClientEnableByEmail(email)
				if needRestart {
					t.xrayService.SetToNeedRestart()
				}
				if err == nil {
					if enabled {
						t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.enableSuccess", "Email=="+email))
					} else {
						t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.disableSuccess", "Email=="+email))
					}
					t.searchClient(chatId, email, callbackQuery.Message.GetMessageID())
				} else {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.errorOperation"))
				}
			case "get_clients":
				inboundId := dataArray[1]
				inboundIdInt, err := strconv.Atoi(inboundId)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				inbound, err := t.inboundService.GetInbound(inboundIdInt)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				clients, err := t.getInboundClients(inboundIdInt)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.chooseClient", "Inbound=="+inbound.Remark), clients)
			case "add_client_to":
				// assign default values to clients variables
				client_Id = uuid.New().String()
				client_Flow = ""
				client_Email = t.randomLowerAndNum(8)
				client_LimitIP = 0
				client_TotalGB = 0
				client_ExpiryTime = 0
				client_Enable = true
				client_TgID = ""
				client_SubID = t.randomLowerAndNum(16)
				client_Comment = ""
				client_Reset = 0
				client_Security = "auto"
				client_ShPassword = t.randomShadowSocksPassword()
				client_TrPassword = t.randomLowerAndNum(10)
				client_Method = ""

				inboundId := dataArray[1]
				inboundIdInt, err := strconv.Atoi(inboundId)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}
				receiver_inbound_ID = inboundIdInt
				inbound, err := t.inboundService.GetInbound(inboundIdInt)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}

				message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return
				}

				t.addClient(callbackQuery.Message.GetChat().ID, message_text)
			}
			return
		} else {
			switch callbackQuery.Data {
			case "get_inbounds":
				inbounds, err := t.getInbounds()
				if err != nil {
					t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
					return

				}
				t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.allClients"))
				t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.chooseInbound"), inbounds)
			}

		}
	}

	switch callbackQuery.Data {
	case "get_usage":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.serverUsage"))
		t.getServerUsage(chatId)
	case "usage_refresh":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
		t.getServerUsage(chatId, callbackQuery.Message.GetMessageID())
	case "inbounds":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.getInbounds"))
		t.SendMsgToTgbot(chatId, t.getInboundUsages())
	case "deplete_soon":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.depleteSoon"))
		t.getExhausted(chatId)
	case "get_backup":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.dbBackup"))
		t.sendBackup(chatId)
	case "get_banlogs":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.getBanLogs"))
		t.sendBanLogs(chatId, true)
	case "client_traffic":
		tgUserID := callbackQuery.From.ID
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.clientUsage"))
		t.getClientUsage(chatId, tgUserID)
	case "client_commands":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.commands"))
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.commands.helpClientCommands"))
	case "onlines":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.onlines"))
		t.onlineClients(chatId)
	case "onlines_refresh":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.successfulOperation"))
		t.onlineClients(chatId, callbackQuery.Message.GetMessageID())
	case "commands":
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.commands"))
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.commands.helpAdminCommands"))
	case "add_client":
		// assign default values to clients variables
		client_Id = uuid.New().String()
		client_Flow = ""
		client_Email = t.randomLowerAndNum(8)
		client_LimitIP = 0
		client_TotalGB = 0
		client_ExpiryTime = 0
		client_Enable = true
		client_TgID = ""
		client_SubID = t.randomLowerAndNum(16)
		client_Comment = ""
		client_Reset = 0
		client_Security = "auto"
		client_ShPassword = t.randomShadowSocksPassword()
		client_TrPassword = t.randomLowerAndNum(10)
		client_Method = ""

		inbounds, err := t.getInboundsAddClient()
		if err != nil {
			t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
			return
		}
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.buttons.addClient"))
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.chooseInbound"), inbounds)
	case "add_client_ch_default_email":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		userStates[chatId] = "awaiting_email"
		cancel_btn_markup := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
			),
		)
		prompt_message := t.I18nBot("tgbot.messages.email_prompt", "ClientEmail=="+client_Email)
		t.SendMsgToTgbot(chatId, prompt_message, cancel_btn_markup)
	case "add_client_ch_default_id":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		userStates[chatId] = "awaiting_id"
		cancel_btn_markup := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
			),
		)
		prompt_message := t.I18nBot("tgbot.messages.id_prompt", "ClientId=="+client_Id)
		t.SendMsgToTgbot(chatId, prompt_message, cancel_btn_markup)
	case "add_client_ch_default_pass_tr":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		userStates[chatId] = "awaiting_password_tr"
		cancel_btn_markup := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
			),
		)
		prompt_message := t.I18nBot("tgbot.messages.pass_prompt", "ClientPassword=="+client_TrPassword)
		t.SendMsgToTgbot(chatId, prompt_message, cancel_btn_markup)
	case "add_client_ch_default_pass_sh":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		userStates[chatId] = "awaiting_password_sh"
		cancel_btn_markup := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
			),
		)
		prompt_message := t.I18nBot("tgbot.messages.pass_prompt", "ClientPassword=="+client_ShPassword)
		t.SendMsgToTgbot(chatId, prompt_message, cancel_btn_markup)
	case "add_client_ch_default_comment":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		userStates[chatId] = "awaiting_comment"
		cancel_btn_markup := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.use_default")).WithCallbackData("add_client_default_info"),
			),
		)
		prompt_message := t.I18nBot("tgbot.messages.comment_prompt", "ClientComment=="+client_Comment)
		t.SendMsgToTgbot(chatId, prompt_message, cancel_btn_markup)
	case "add_client_ch_default_traffic":
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_traffic_exp")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 0")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("add_client_limit_traffic_in 0")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("1 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 1")),
				tu.InlineKeyboardButton("5 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 5")),
				tu.InlineKeyboardButton("10 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 10")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("20 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 20")),
				tu.InlineKeyboardButton("30 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 30")),
				tu.InlineKeyboardButton("40 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 40")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("50 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 50")),
				tu.InlineKeyboardButton("60 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 60")),
				tu.InlineKeyboardButton("80 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 80")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("100 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 100")),
				tu.InlineKeyboardButton("150 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 150")),
				tu.InlineKeyboardButton("200 GB").WithCallbackData(t.encodeQuery("add_client_limit_traffic_c 200")),
			),
		)
		t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
	case "add_client_ch_default_exp":
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_traffic_exp")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 0")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("add_client_reset_exp_in 0")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 7 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 7")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 10 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 10")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 14 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 14")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 20 "+t.I18nBot("tgbot.days")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 20")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 1 "+t.I18nBot("tgbot.month")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 30")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 3 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 90")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 6 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 180")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.add")+" 12 "+t.I18nBot("tgbot.months")).WithCallbackData(t.encodeQuery("add_client_reset_exp_c 365")),
			),
		)
		t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
	case "add_client_ch_default_ip_limit":
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData(t.encodeQuery("add_client_default_ip_limit")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.unlimited")).WithCallbackData(t.encodeQuery("add_client_ip_limit_c 0")),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.custom")).WithCallbackData(t.encodeQuery("add_client_ip_limit_in 0")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("1").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 1")),
				tu.InlineKeyboardButton("2").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 2")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("3").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 3")),
				tu.InlineKeyboardButton("4").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 4")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("5").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 5")),
				tu.InlineKeyboardButton("6").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 6")),
				tu.InlineKeyboardButton("7").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 7")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("8").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 8")),
				tu.InlineKeyboardButton("9").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 9")),
				tu.InlineKeyboardButton("10").WithCallbackData(t.encodeQuery("add_client_ip_limit_c 10")),
			),
		)
		t.editMessageCallbackTgBot(chatId, callbackQuery.Message.GetMessageID(), inlineKeyboard)
	case "add_client_default_info":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.SendMsgToTgbotDeleteAfter(chatId, t.I18nBot("tgbot.messages.using_default_value"), 3, tu.ReplyKeyboardRemove())
		delete(userStates, chatId)
		inbound, _ := t.inboundService.GetInbound(receiver_inbound_ID)
		message_text, _ := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
		t.addClient(chatId, message_text)
	case "add_client_cancel":
		delete(userStates, chatId)
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.SendMsgToTgbotDeleteAfter(chatId, t.I18nBot("tgbot.messages.cancel"), 3, tu.ReplyKeyboardRemove())
	case "add_client_default_traffic_exp":
		messageId := callbackQuery.Message.GetMessageID()
		inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
		if err != nil {
			t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
			return
		}
		message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
		if err != nil {
			t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
			return
		}
		t.addClient(chatId, message_text, messageId)
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.canceled", "Email=="+client_Email))
	case "add_client_default_ip_limit":
		messageId := callbackQuery.Message.GetMessageID()
		inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
		if err != nil {
			t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
			return
		}
		message_text, err := t.BuildInboundClientDataMessage(inbound.Remark, inbound.Protocol)
		if err != nil {
			t.sendCallbackAnswerTgBot(callbackQuery.ID, err.Error())
			return
		}
		t.addClient(chatId, message_text, messageId)
		t.sendCallbackAnswerTgBot(callbackQuery.ID, t.I18nBot("tgbot.answers.canceled", "Email=="+client_Email))
	case "add_client_submit_disable":
		client_Enable = false
		_, err := t.SubmitAddClient()
		if err != nil {
			errorMessage := fmt.Sprintf("%v", err)
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.messages.error_add_client", "error=="+errorMessage), tu.ReplyKeyboardRemove())
		} else {
			t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.successfulOperation"), tu.ReplyKeyboardRemove())
		}
	case "add_client_submit_enable":
		client_Enable = true
		_, err := t.SubmitAddClient()
		if err != nil {
			errorMessage := fmt.Sprintf("%v", err)
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.messages.error_add_client", "error=="+errorMessage), tu.ReplyKeyboardRemove())
		} else {
			t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.successfulOperation"), tu.ReplyKeyboardRemove())
		}
	case "reset_all_traffics_cancel":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.SendMsgToTgbotDeleteAfter(chatId, t.I18nBot("tgbot.messages.cancel"), 1, tu.ReplyKeyboardRemove())
	case "reset_all_traffics":
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancelReset")).WithCallbackData(t.encodeQuery("reset_all_traffics_cancel")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.confirmResetTraffic")).WithCallbackData(t.encodeQuery("reset_all_traffics_c")),
			),
		)
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.messages.AreYouSure"), inlineKeyboard)
	case "reset_all_traffics_c":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		emails, err := t.inboundService.getAllEmails()
		if err != nil {
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.errorOperation"), tu.ReplyKeyboardRemove())
			return
		}

		for _, email := range emails {
			err := t.inboundService.ResetClientTrafficByEmail(email)
			if err == nil {
				msg := t.I18nBot("tgbot.messages.SuccessResetTraffic", "ClientEmail=="+email)
				t.SendMsgToTgbot(chatId, msg, tu.ReplyKeyboardRemove())
			} else {
				msg := t.I18nBot("tgbot.messages.FailedResetTraffic", "ClientEmail=="+email, "ErrorMessage=="+err.Error())
				t.SendMsgToTgbot(chatId, msg, tu.ReplyKeyboardRemove())
			}
		}

		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.messages.FinishProcess"), tu.ReplyKeyboardRemove())
	case "get_sorted_traffic_usage_report":
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		emails, err := t.inboundService.getAllEmails()

		if err != nil {
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.errorOperation"), tu.ReplyKeyboardRemove())
			return
		}
		valid_emails, extra_emails, err := t.inboundService.FilterAndSortClientEmails(emails)
		if err != nil {
			t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.errorOperation"), tu.ReplyKeyboardRemove())
			return
		}
		
		for _, valid_emails := range valid_emails {
			traffic, err := t.inboundService.GetClientTrafficByEmail(valid_emails)
			if err != nil {
				logger.Warning(err)
				msg := t.I18nBot("tgbot.wentWrong")
				t.SendMsgToTgbot(chatId, msg)
				continue
			}
			if traffic == nil {
				msg := t.I18nBot("tgbot.noResult")
				t.SendMsgToTgbot(chatId, msg)
				continue
			}

			output := t.clientInfoMsg(traffic, false, false, false, false, true, false)
			t.SendMsgToTgbot(chatId, output, tu.ReplyKeyboardRemove())
		}
		for _, extra_emails := range extra_emails {
			msg := fmt.Sprintf("📧 %s\n%s", extra_emails, t.I18nBot("tgbot.noResult"))
			t.SendMsgToTgbot(chatId, msg, tu.ReplyKeyboardRemove())

		}

	// 〔中文注释〕: 新增 - 处理用户点击 "玩" 抽奖游戏
	case "lottery_play":
		
		// 确保本次 Shuffle 是随机的。
		rng.Seed(time.Now().UnixNano()) 
		chatId := callbackQuery.Message.GetChat().ID // 【确保 chatId 在函数开始时被初始化】
		messageId := callbackQuery.Message.GetMessageID() // 获取原消息 ID
		
		// 〔中文注释〕: 首先，回应 TG 的回调请求，告诉用户机器人已收到操作。
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "〔X-Panel 小白哥〕正在为您摇奖，请稍后......")
		
		// 这条消息会永久停留在聊天窗口，作为等待提示。
		t.editMessageTgBot(
			chatId,
			messageId,
			"⏳ **抽奖结果生成中...**\n\n------->>>请耐心等待 5 秒......\n\n〔X-Panel 小白哥〕马上为您揭晓！",
			// 【关键】: 不传入键盘参数，自动移除旧键盘
		)

		// --- 【发送动态贴纸（实现随机、容错、不中断）】 ---
		var stickerMessageID int // 用于存储成功发送的贴纸消息 ID
		
        // 〔中文注释〕: 1. 将数组转换为可操作的切片
		stickerIDsSlice := LOTTERY_STICKER_IDS[:] 

		// 〔中文注释〕: 2. 随机化贴纸的发送顺序，确保每次动画不同。
		// 注意: 依赖于文件头部导入的 rng "math/rand"
		rng.Shuffle(len(stickerIDsSlice), func(i, j int) {
			stickerIDsSlice[i], stickerIDsSlice[j] = stickerIDsSlice[j], stickerIDsSlice[i]
		})
        
		// 〔中文注释〕: 3. 遍历随机化后的贴纸 ID，尝试发送，直到成功为止。
		for _, stickerID := range stickerIDsSlice {
			stickerMessage, err := t.SendStickerToTgbot(chatId, stickerID)
			if err == nil {
				// 成功发送，记录 ID 并跳出循环。
				stickerMessageID = stickerMessage.MessageID
				break
			}
			// 如果失败，记录日志并尝试下一个 ID。
			logger.Warningf("尝试发送贴纸 %s 失败: %v", stickerID, err)
		}
		
		// 【保持】: 程序在此处暂停 5 秒，用户可以看到动画。
		time.Sleep(5000 * time.Millisecond)
		
		// 【新增：5秒后，删除动画贴纸】
		if stickerMessageID != 0 {
			// 〔中文注释〕: 抽奖结束后，删除刚才成功发送的动态贴纸消息。
			t.deleteMessageTgBot(chatId, stickerMessageID)
		}
    
        // 程序将在 5 秒后，继续执行下面的逻辑：
		userID := callbackQuery.From.ID

		// --- 【新增】: 获取用户信息，用于防伪 ---
		user := callbackQuery.From
		// 优先使用 Username，如果没有则使用 FirstName
		userInfo := user.FirstName
		if user.Username != "" {
			userInfo = "@" + user.Username
		}

		
		// 〔中文注释〕: 检查用户今天是否已经中过奖 (调用您在 database 中实现的函数)。
		hasWon, err := database.HasUserWonToday(userID)
		    if err != nil {
				logger.Warningf("查询用户 %d 中奖记录失败: %v", userID, err)
				t.editMessageTgBot(chatId, callbackQuery.Message.GetMessageID(), "抱歉，抽奖数据库查询失败，请联系管理员。")
				return
			}

			if hasWon {
				// 〔中文注释〕: 如果已经中奖，则告知用户并结束。
				t.editMessageTgBot(chatId, callbackQuery.Message.GetMessageID(), "您今天已经中过奖啦，请明天再来！\n\n机会还多的是，贪心可是不好的哦~")
				return
			}

			// 〔中文注释〕: 执行抽奖逻辑。
			prize, resultMessage := t.runLotteryDraw()

			// 〔中文注释〕: 如果中奖了（不是 "未中奖" 或 "错误"）。
			if prize != "未中奖" && prize != "错误" {

			// --- 【新增】: 获取当前时间并格式化 ---
			winningTime := time.Now().Format("2006-01-02 15:04:05")	
				
			// --- 【新增】: 生成防伪校验哈希 ---
			// 1. 组合所有关键信息：UserID + Prize + WinningTime
			//    注意：使用 prize 而不是 resultMessage，因为 prize 是干净的奖项名称。
			dataToHash := strconv.FormatInt(user.ID, 10) + "|" + prize + "|" + winningTime
			
			// 2. 计算 SHA256 哈希值
			hasher := sha256.New()
			hasher.Write([]byte(dataToHash))
			// 3. 转换为 16 进制字符串（方便显示）
			validationHash := hex.EncodeToString(hasher.Sum(nil))[:16] // 取前16位简化显示	

			// --- 拼接最终的中奖消息，将用户唯一标识添加到兑奖说明前 ---
			finalMessage := resultMessage + "\n\n" +
							"**中奖用户**: " + userInfo + "\n\n" +
							"**TG用户ID**: `" + strconv.FormatInt(user.ID, 10) + "`\n\n" +
				            "**中奖时间**: " + winningTime + "\n\n" +
				            "**防伪码 (Hash)**: `" + validationHash + "`\n\n" +
							"**兑奖说明**：请截图此完整消息，\n\n" +
							"并联系交流群内管理员进行兑奖。\n\n" +
							"------------->>>>〔X-Panel 面板〕交流群：\n\n" +
							"------------->>>> https://t.me/XUI_CN"

			// --- 【向中央统计频道发送报告（异步）】 ---
			go func() {
				// 尝试获取主机名作为唯一标识
				vpsIdentifier, err := os.Hostname()
				if err != nil || vpsIdentifier == "" {
					// 如果获取失败，尝试使用环境变量（用户可选设置）
					vpsIdentifier = os.Getenv("VPS_IDENTIFIER")
					if vpsIdentifier == "" {
						// 如果都失败，使用一个通用标识
						vpsIdentifier = "UNKNOWN_HOST"
					}
				}

				reportMessage := fmt.Sprintf(
					"✅ **[中奖报告 - %s]**\n\n" +
					"**用户名**: `%s`\n\n" +
					"**用户ID**: `%d`\n\n" +
					"**中奖时间**: %s\n\n" + 
					"**部署来源**: `%s`", // 自动获取的主机名
					prize,
					userInfo,
					userID,
					winningTime,
					vpsIdentifier,
				)
				// --- 【核心】: 创建一个临时的、专用于报告的机器人实例 ---
		        reportBot, err := telego.NewBot(REPORT_BOT_TOKEN)
		        if err != nil {
			        logger.Errorf("无法创建报告机器人实例: %v", err)
			        return // 如果无法创建报告机器人，则静默失败，不影响用户
		        }

				// --- 遍历所有报告频道 ID 并发送 ---
				for _, chatID := range REPORT_CHAT_IDS {
					// 构建正确的 SendMessageParams
					params := tu.Message(tu.ID(chatID), reportMessage).WithParseMode(telego.ModeMarkdown)

					// 使用临时机器人的 SendMessage 方法发送报告
					_, err = reportBot.SendMessage(context.Background(), params)
					if err != nil {
						logger.Warningf("发送【中奖报告】到频道 %d 失败: %v", chatID, err)
					}
				}	
	        }() // 异步执行结束
					
			// 〔中文注释〕: 记录中奖结果 (调用在 database 中实现的函数)。
			err := database.RecordUserWin(userID, prize)
			if err != nil {
				logger.Warningf("记录用户 %d 中奖信息失败: %v", userID, err)
				// 〔中文注释〕: 即使记录失败，也要告知用户中奖了，但提示管理员后台可能出错了。
				finalMessage += "\n\n(后台警告：数据库记录失败，请管理员手动核实给予兑奖)"
			}
			// 〔中文注释〕: 编辑原消息，显示最终的中奖结果。
				t.editMessageTgBot(chatId, callbackQuery.Message.GetMessageID(), finalMessage)
			} else {
				// 〔中文注释〕: 如果未中奖或抽奖出错，则直接显示相应信息。
				t.editMessageTgBot(chatId, callbackQuery.Message.GetMessageID(), resultMessage)

				// --- 【新增：未中奖也发送报告到中央频道（异步）】 ---
				go func() {
					// 尝试获取主机名作为唯一标识
					vpsIdentifier, err := os.Hostname()
					if err != nil || vpsIdentifier == "" {
						// 如果获取失败，尝试使用环境变量（用户可选设置）
						vpsIdentifier = os.Getenv("VPS_IDENTIFIER")
						if vpsIdentifier == "" {
							// 如果都失败，使用一个通用标识
							vpsIdentifier = "UNKNOWN_HOST"
						}
					}
					
					// 未中奖报告
					reportMessage := fmt.Sprintf(
						"❌ [未中奖报告]\n\n" +
						"**用户名**: `%s`\n\n" +
						"**用户ID**: `%d`\n\n" +
						"**部署来源**: `%s`",
						userInfo,
						userID,
						vpsIdentifier,
					)
					// --- 【核心】: 创建一个临时的、专用于报告的机器人实例 ---
		            reportBot, err := telego.NewBot(REPORT_BOT_TOKEN)
		            if err != nil {
			            logger.Errorf("无法创建报告机器人实例: %v", err)
			            return // 如果无法创建报告机器人，则静默失败，不影响用户
		            }

				    // --- 遍历所有报告频道 ID 并发送 ---
					for _, chatID := range REPORT_CHAT_IDS {
						// 构建正确的 SendMessageParams
						params := tu.Message(tu.ID(chatID), reportMessage).WithParseMode(telego.ModeMarkdown)

						// 使用临时机器人的 SendMessage 方法发送报告
						_, err = reportBot.SendMessage(context.Background(), params)
						if err != nil {
							logger.Warningf("发送【未中奖报告】到频道 %d 失败: %v", chatID, err)
						}
					}	
	           }() // 异步执行结束
			}
			return // 〔中文注释〕: 处理完毕，直接返回，避免执行后续逻辑。

	 // 〔中文注释〕: 新增 - 处理用户点击 "不玩" 抽奖游戏
	 case "lottery_skip":
			// 〔中文注释〕: 回应回调请求。
			t.sendCallbackAnswerTgBot(callbackQuery.ID, "您已跳过游戏。")
			// 〔中文注释〕: 编辑原消息，移除按钮并显示友好提示。
			t.editMessageTgBot(chatId, callbackQuery.Message.GetMessageID(), "您选择不参与本次游戏，祝您一天愉快！")
			return // 〔中文注释〕: 处理完毕，直接返回。	

	 // 【新增代码】: 在这里处理新按钮的回调
	 case "oneclick_options":
		 t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		 t.sendCallbackAnswerTgBot(callbackQuery.ID, "功能升级提示......")
		 t.SendMsgToTgbot(chatId, "〔一键配置〕功能现已升级为“付费Pro版”专属功能，\n\n请联系面板管理员〔购买授权码〕之后才能继续使用，\n\n----->>> 面板管理员私聊机器人：@is_Chat_Bot")

	 case "subconverter_install":
		 t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		 t.sendCallbackAnswerTgBot(callbackQuery.ID, "🔄 正在检查服务...")
		 t.checkAndInstallSubconverter(chatId)

	 case "confirm_sub_install":
		 t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		 t.sendCallbackAnswerTgBot(callbackQuery.ID, "✅ 指令已发送")
		 t.SendMsgToTgbot(chatId, "【订阅转换】模块正在后台安装，大约需要1-2分钟，完成后将再次通知您。")
		    err := t.serverService.InstallSubconverter()
			if err != nil {
				t.SendMsgToTgbot(chatId, fmt.Sprintf("发送安装指令失败: %v", err))
			}

	 case "cancel_sub_install":
		 t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		 t.sendCallbackAnswerTgBot(callbackQuery.ID, "已取消")
		 t.SendMsgToTgbot(chatId, "已取消【订阅转换】安装操作。")
	// 〔中文注释〕: 【新增回调处理】 - 重启面板、娱乐抽奖、VPS推荐
	case "restart_panel":
		// 〔中文注释〕: 用户从菜单点击重启，删除主菜单并发送确认消息
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "请确认操作")
		confirmKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("✅ 是，立即重启").WithCallbackData(t.encodeQuery("restart_panel_confirm")),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton("❌ 否，我再想想").WithCallbackData(t.encodeQuery("restart_panel_cancel")),
			),
		)
		t.SendMsgToTgbot(chatId, "🤔 您“现在的操作”是要确定进行，\n\n重启〔X-Panel 面板〕服务吗？\n\n这也会同时重启 Xray Core，\n\n会使面板在短时间内无法访问。", confirmKeyboard)

	case "restart_panel_confirm":
		// 〔中文注释〕: 用户确认重启
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "指令已发送，请稍候...")
		t.SendMsgToTgbot(chatId, "⏳ 【重启命令】已在 VPS 中远程执行，\n\n正在等待面板恢复（约30秒），并进行验证检查...")

		// 〔中文注释〕: 在后台协程中执行重启，避免阻塞机器人
		go func() {
			err := t.serverService.RestartPanel()
			// 〔中文注释〕: 等待20秒，让面板有足够的时间重启
			time.Sleep(20 * time.Second)
			if err != nil {
				// 〔中文注释〕: 如果执行出错，发送失败消息
				t.SendMsgToTgbot(chatId, fmt.Sprintf("❌ 面板重启命令执行失败！\n\n错误信息已记录到日志，请检查命令或权限。\n\n`%v`", err))
			} else {
				// 〔中文注释〕: 执行成功，发送成功消息
				t.SendMsgToTgbot(chatId, "🚀 面板重启成功！服务已成功恢复！")
			}
		}()

	case "restart_panel_cancel":
		// 〔中文注释〕: 用户取消重启
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "操作已取消")
		// 〔中文注释〕: 发送一个临时消息提示用户，3秒后自动删除
		t.SendMsgToTgbotDeleteAfter(chatId, "已取消重启操作。", 3)

	case "lottery_play_menu":
		// 〔中文注释〕: 从菜单触发抽奖，复用现有逻辑
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "正在准备游戏......")
		// 〔中文注释〕: 直接调用您代码中已有的 sendLotteryGameInvitation 函数即可
		t.sendLotteryGameInvitation()

	case "vps_recommend":
		// 〔中文注释〕: 发送您指定的VPS推荐信息
		t.deleteMessageTgBot(chatId, callbackQuery.Message.GetMessageID())
		t.sendCallbackAnswerTgBot(callbackQuery.ID, "请查看VPS推荐列表")
		vpsMessage := `✰若需要购买VPS，以下可供选择（包含AFF）✰

1、搬瓦工GIA高端线路，仅推荐购买GIA套餐：
https://bandwagonhost.com/aff.php?aff=75015

2、Dmit高端GIA线路：
https://www.dmit.io/aff.php?aff=9326

3、Sharon亚太优化线路机：
https://gomami.io/aff.php?aff=174

4、Bagevm优质落地鸡（原生IP全解锁）：
https://www.bagevm.com/aff.php?aff=754

5、白丝云【4837线路】实惠量大管饱：
https://cloudsilk.io/aff.php?aff=706

6、RackNerd极致性价比机器：
https://my.racknerd.com/aff.php?aff=15268&pid=912`
		// 〔中文注释〕: 发送消息时禁用链接预览，使界面更整洁
		params := tu.Message(
			tu.ID(chatId),
			vpsMessage,
		).WithLinkPreviewOptions(&telego.LinkPreviewOptions{IsDisabled: true})

		_, err := bot.SendMessage(context.Background(), params)
		if err != nil {
			logger.Warning("发送VPS推荐消息失败:", err)
		}	
	}
}

func (t *Tgbot) BuildInboundClientDataMessage(inbound_remark string, protocol model.Protocol) (string, error) {
	var message string

	currentTime := time.Now()
	timestampMillis := currentTime.UnixNano() / int64(time.Millisecond)

	expiryTime := ""
	diff := client_ExpiryTime/1000 - timestampMillis
	if client_ExpiryTime == 0 {
		expiryTime = t.I18nBot("tgbot.unlimited")
	} else if diff > 172800 {
		expiryTime = time.Unix((client_ExpiryTime / 1000), 0).Format("2006-01-02 15:04:05")
	} else if client_ExpiryTime < 0 {
		expiryTime = fmt.Sprintf("%d %s", client_ExpiryTime/-86400000, t.I18nBot("tgbot.days"))
	} else {
		expiryTime = fmt.Sprintf("%d %s", diff/3600, t.I18nBot("tgbot.hours"))
	}

	traffic_value := ""
	if client_TotalGB == 0 {
		traffic_value = "♾️ Unlimited(Reset)"
	} else {
		traffic_value = common.FormatTraffic(client_TotalGB)
	}

	ip_limit := ""
	if client_LimitIP == 0 {
		ip_limit = "♾️ Unlimited(Reset)"
	} else {
		ip_limit = fmt.Sprint(client_LimitIP)
	}

	switch protocol {
	case model.VMESS, model.VLESS:
		message = t.I18nBot("tgbot.messages.inbound_client_data_id", "InboundRemark=="+inbound_remark, "ClientId=="+client_Id, "ClientEmail=="+client_Email, "ClientTraffic=="+traffic_value, "ClientExp=="+expiryTime, "IpLimit=="+ip_limit, "ClientComment=="+client_Comment)

	case model.Trojan:
		message = t.I18nBot("tgbot.messages.inbound_client_data_pass", "InboundRemark=="+inbound_remark, "ClientPass=="+client_TrPassword, "ClientEmail=="+client_Email, "ClientTraffic=="+traffic_value, "ClientExp=="+expiryTime, "IpLimit=="+ip_limit, "ClientComment=="+client_Comment)

	case model.Shadowsocks:
		message = t.I18nBot("tgbot.messages.inbound_client_data_pass", "InboundRemark=="+inbound_remark, "ClientPass=="+client_ShPassword, "ClientEmail=="+client_Email, "ClientTraffic=="+traffic_value, "ClientExp=="+expiryTime, "IpLimit=="+ip_limit, "ClientComment=="+client_Comment)

	default:
		return "", errors.New("unknown protocol")
	}

	return message, nil
}

func (t *Tgbot) BuildJSONForProtocol(protocol model.Protocol) (string, error) {
	var jsonString string

	switch protocol {
	case model.VMESS:
		jsonString = fmt.Sprintf(`{
            "clients": [{
                "id": "%s",
                "security": "%s",
                "email": "%s",
                "limitIp": %d,
                "totalGB": %d,
                "expiryTime": %d,
                "enable": %t,
                "tgId": "%s",
                "subId": "%s",
                "comment": "%s",
                "reset": %d
            }]
        }`, client_Id, client_Security, client_Email, client_LimitIP, client_TotalGB, client_ExpiryTime, client_Enable, client_TgID, client_SubID, client_Comment, client_Reset)

	case model.VLESS:
		jsonString = fmt.Sprintf(`{
            "clients": [{
                "id": "%s",
                "flow": "%s",
                "email": "%s",
                "limitIp": %d,
                "totalGB": %d,
                "expiryTime": %d,
                "enable": %t,
                "tgId": "%s",
                "subId": "%s",
                "comment": "%s",
                "reset": %d
            }]
        }`, client_Id, client_Flow, client_Email, client_LimitIP, client_TotalGB, client_ExpiryTime, client_Enable, client_TgID, client_SubID, client_Comment, client_Reset)

	case model.Trojan:
		jsonString = fmt.Sprintf(`{
            "clients": [{
                "password": "%s",
                "email": "%s",
                "limitIp": %d,
                "totalGB": %d,
                "expiryTime": %d,
                "enable": %t,
                "tgId": "%s",
                "subId": "%s",
                "comment": "%s",
                "reset": %d
            }]
        }`, client_TrPassword, client_Email, client_LimitIP, client_TotalGB, client_ExpiryTime, client_Enable, client_TgID, client_SubID, client_Comment, client_Reset)

	case model.Shadowsocks:
		jsonString = fmt.Sprintf(`{
            "clients": [{
                "method": "%s",
                "password": "%s",
                "email": "%s",
                "limitIp": %d,
                "totalGB": %d,
                "expiryTime": %d,
                "enable": %t,
                "tgId": "%s",
                "subId": "%s",
                "comment": "%s",
                "reset": %d
            }]
        }`, client_Method, client_ShPassword, client_Email, client_LimitIP, client_TotalGB, client_ExpiryTime, client_Enable, client_TgID, client_SubID, client_Comment, client_Reset)

	default:
		return "", errors.New("unknown protocol")
	}

	return jsonString, nil
}

func (t *Tgbot) SubmitAddClient() (bool, error) {

	inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
	if err != nil {
		logger.Warning("getIboundClients run failed:", err)
		return false, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}

	jsonString, err := t.BuildJSONForProtocol(inbound.Protocol)
	if err != nil {
		logger.Warning("BuildJSONForProtocol run failed:", err)
		return false, errors.New("failed to build JSON for protocol")
	}

	newInbound := &model.Inbound{
		Id:       receiver_inbound_ID,
		Settings: jsonString,
	}

	return t.inboundService.AddInboundClient(newInbound)
}

func checkAdmin(tgId int64) bool {
	for _, adminId := range adminIds {
		if adminId == tgId {
			return true
		}
	}
	return false
}

func (t *Tgbot) SendAnswer(chatId int64, msg string, isAdmin bool) {
	numericKeyboard := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.serverUsage")).WithCallbackData(t.encodeQuery("get_usage")),
			tu.InlineKeyboardButton("♻️ 重启面板").WithCallbackData(t.encodeQuery("restart_panel")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.SortedTrafficUsageReport")).WithCallbackData(t.encodeQuery("get_sorted_traffic_usage_report")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.ResetAllTraffics")).WithCallbackData(t.encodeQuery("reset_all_traffics")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.dbBackup")).WithCallbackData(t.encodeQuery("get_backup")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.getBanLogs")).WithCallbackData(t.encodeQuery("get_banlogs")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.getInbounds")).WithCallbackData(t.encodeQuery("inbounds")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.depleteSoon")).WithCallbackData(t.encodeQuery("deplete_soon")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.commands")).WithCallbackData(t.encodeQuery("commands")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.onlines")).WithCallbackData(t.encodeQuery("onlines")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.allClients")).WithCallbackData(t.encodeQuery("get_inbounds")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.addClient")).WithCallbackData(t.encodeQuery("add_client")),
		),
		// 【一键配置】和【订阅转换】按钮的回调数据
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.oneClick")).WithCallbackData(t.encodeQuery("oneclick_options")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.subconverter")).WithCallbackData(t.encodeQuery("subconverter_install")),
		),
		// 〔中文注释〕: 【新增功能行】 - 添加娱乐抽奖和VPS推荐按钮
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton("🎁 娱乐抽奖").WithCallbackData(t.encodeQuery("lottery_play_menu")),
			tu.InlineKeyboardButton("🛰️ VPS 推荐").WithCallbackData(t.encodeQuery("vps_recommend")),
		),
		// TODOOOOOOOOOOOOOO: Add restart button here.
	)
	numericKeyboardClient := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.clientUsage")).WithCallbackData(t.encodeQuery("client_traffic")),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.commands")).WithCallbackData(t.encodeQuery("client_commands")),
		),
	)

	var ReplyMarkup telego.ReplyMarkup
	if isAdmin {
		ReplyMarkup = numericKeyboard
	} else {
		ReplyMarkup = numericKeyboardClient
	}
	t.SendMsgToTgbot(chatId, msg, ReplyMarkup)
}

func (t *Tgbot) SendMsgToTgbot(chatId int64, msg string, replyMarkup ...telego.ReplyMarkup) {
	if !isRunning {
		return
	}

	if msg == "" {
		logger.Info("[tgbot] message is empty!")
		return
	}

	var allMessages []string
	limit := 2000

	// paging message if it is big
	if len(msg) > limit {
		messages := strings.Split(msg, "\r\n\r\n")
		lastIndex := -1

		for _, message := range messages {
			if (len(allMessages) == 0) || (len(allMessages[lastIndex])+len(message) > limit) {
				allMessages = append(allMessages, message)
				lastIndex++
			} else {
				allMessages[lastIndex] += "\r\n\r\n" + message
			}
		}
		if strings.TrimSpace(allMessages[len(allMessages)-1]) == "" {
			allMessages = allMessages[:len(allMessages)-1]
		}
	} else {
		allMessages = append(allMessages, msg)
	}
	for n, message := range allMessages {
		params := telego.SendMessageParams{
			ChatID:    tu.ID(chatId),
			Text:      message,
			ParseMode: "HTML",
		}
		// only add replyMarkup to last message
		if len(replyMarkup) > 0 && n == (len(allMessages)-1) {
			params.ReplyMarkup = replyMarkup[0]
		}
		_, err := bot.SendMessage(context.Background(), &params)
		if err != nil {
			logger.Warning("Error sending telegram message :", err)
		}
		time.Sleep(500 * time.Millisecond)
	}
}

func (t *Tgbot) SendMsgToTgbotAdmins(msg string, replyMarkup ...telego.ReplyMarkup) {
	if len(replyMarkup) > 0 {
		for _, adminId := range adminIds {
			t.SendMsgToTgbot(adminId, msg, replyMarkup[0])
		}
	} else {
		for _, adminId := range adminIds {
			t.SendMsgToTgbot(adminId, msg)
		}
	}
}

// 〔中文注释〕: 全新重构的 SendReport 函数，只发送四条趣味性内容。
func (t *Tgbot) SendReport() {

	// --- 向中央统计频道发送心跳报告（异步） ---
	go func() {
		// 1. 尝试获取主机名作为唯一标识
		vpsIdentifier, err := os.Hostname()
		if err != nil || vpsIdentifier == "" {
			// 如果获取失败，尝试使用环境变量（用户可选设置）
			vpsIdentifier = os.Getenv("VPS_IDENTIFIER")
			if vpsIdentifier == "" {
				// 如果都失败，使用一个通用标识
				vpsIdentifier = "UNKNOWN_HOST"
			}
		}

		// 2. 准备报告消息
		reportMessage := fmt.Sprintf(
			"🟢 **[心跳报告]**\n\n" +
			"**时间**: `%s`\n\n" +
			"**部署来源**: `%s`", // 独一无二的主机名
			time.Now().Format("2006-01-02 15:04:05"),
			vpsIdentifier,
		)

		// --- 【核心修正】: 创建一个临时的、专用于报告的机器人实例 ---
		reportBot, err := telego.NewBot(REPORT_BOT_TOKEN)
		if err != nil {
			logger.Errorf("无法创建报告机器人实例: %v", err)
			return // 如果无法创建报告机器人，则静默失败，不影响用户
		}

		// --- 遍历所有报告频道 ID 并发送 ---
		for _, chatID := range REPORT_CHAT_IDS {
			// 构建正确的 SendMessageParams
			params := tu.Message(tu.ID(chatID), reportMessage).WithParseMode(telego.ModeMarkdown)

			// 使用临时机器人的 SendMessage 方法发送报告
			_, err = reportBot.SendMessage(context.Background(), params)
			if err != nil {
				logger.Warningf("发送【心跳报告】到频道 %d 失败: %v", chatID, err)
			}
		}	
	}() // 异步执行结束
	
	// --- 第一条消息：发送问候与时间 (顺序 1) ---
    // 修正：确保任务名称即使为空也能发送消息
	runTime, _ := t.settingService.GetTgbotRuntime() 
    taskName := runTime
    if taskName == "" {
        taskName = "未配置任务名称" // 使用占位符，避免因空值跳过
    }

	greetingMsg := fmt.Sprintf(
		"☀️ **每日定时报告** (任务: `%s`)\n\n*  美好的一天，从〔X-Panel 面板〕开始！*\n\n⏰ **当前时间**：`%s`",
		taskName,
		time.Now().Format("2006-01-02 15:04:05"),
	)
	t.SendMsgToTgbotAdmins(greetingMsg) 
	time.Sleep(1000 * time.Millisecond)

	// --- 第二条消息：每日一语（最终稳定版） (顺序 2) ---
	if verse, err := t.getDailyVerse(); err == nil {
		t.SendMsgToTgbotAdmins(verse)
	} else {
		// 即使失败，也记录日志，不影响后续发送
		logger.Warningf("获取每日诗词失败: %v", err)
	}
	time.Sleep(1000 * time.Millisecond)

	// --- 第三条消息：今日美图（三重冗余，已修复） (顺序 3) ---
	t.sendRandomImageWithFallback()
	time.Sleep(1000 * time.Millisecond)

	// --- 第四条消息：新闻资讯简报（最终稳定版：中文 IT/AI/币圈） (顺序 4) ---
	if news, err := t.getNewsBriefingWithFallback(); err == nil {
		t.SendMsgToTgbotAdmins(news)
	} else {
		// 即使失败，也记录日志，不影响发送流程结束
		logger.Warningf("获取所有新闻资讯失败: %v", err)
	}
	// 〔中文注释〕: 【新增】为下一条消息添加延时
	time.Sleep(1000 * time.Millisecond)

	// --- 【新增】第五条消息：发送抽奖游戏邀请 (顺序 5) ---
	t.sendLotteryGameInvitation()
}

// 〔中文注释〕: 新增函数，执行抽奖逻辑并返回结果。
func (t *Tgbot) runLotteryDraw() (prize string, message string) {
	// 〔中文注释〕: 使用 crypto/rand 生成一个 0-999 的安全随机数，确保公平性。
	n, err := rand.Int(rand.Reader, big.NewInt(1000))
    if err != nil {
        logger.Warningf("生成抽奖随机数失败: %v", err)
        // 〔中文注释〕: 如果安全随机数生成失败，返回一个错误提示，避免继续执行。
        return "错误", "抽奖系统暂时出现问题，请联系管理员。"
    }
	roll := n.Int64()

	// 〔中文注释〕: 设置不同奖项的中奖概率。总中奖概率：3%+8%+12%+20%=43% 。
	// 一等奖: 30/1000 (3%)
	if roll < 30 {
		prize = "一等奖"
		message = "🎉 **天选之人！恭喜您抽中【一等奖】！** 🎉\n\n请联系管理员兑换神秘大奖！"
		return
	}
	// 二等奖: 80/1000 (8%)，累计上限 110
	if roll < 110 {
		prize = "二等奖"
		message = "🎊 **欧气满满！恭喜您抽中【二等奖】！** 🎊\n\n请联系管理员兑换牛逼奖品！"
		return
	}
	// 三等奖: 120/1000 (12%)，累计上限 230
	if roll < 230 {
		prize = "三等奖"
		message = "🎁 **运气不错！恭喜您抽中【三等奖】！** 🎁\n\n请联系管理员兑换小惊喜！"
		return
	}
	// 安慰奖: 200/1000 (20%)，累计上限 430
	if roll < 430 {
		prize = "安慰奖"
		message = "👍 **重在参与！恭喜您抽中【安慰奖】！** 👍\n\n请联系管理员兑换鼓励奖！"
		return
	}

	// 〔中文注释〕: 如果未中任何奖项。未中奖概率 57% 。
	prize = "未中奖"
	message = "😕 **谢谢参与**倒霉的宝子。\n\n很遗憾，本次您未中奖，明天再来试试吧！"
	return
}

// 〔中文注释〕: 新增函数，用于发送抽奖游戏邀请。
func (t *Tgbot) sendLotteryGameInvitation() {
	// 〔中文注释〕: 构建邀请消息和内联键盘。
	msg := "-------🎉 福利区 🎉-------\n\n✨ **每日幸运抽奖游戏**\n\n-->您想试试今天的手气吗？"

	// 〔中文注释〕: "lottery_play" 和 "lottery_skip" 将作为回调数据，用于后续处理。
	inlineKeyboard := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton("🤩玩，我要赢奖品/萝莉！！！").WithCallbackData(t.encodeQuery("lottery_play")),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton("❌劳资不玩，我要看美图......").WithCallbackData(t.encodeQuery("lottery_skip")),
		),
	)

	// 〔中文注释〕: 将带键盘的消息发送给所有管理员。
	t.SendMsgToTgbotAdmins(msg, inlineKeyboard)
}

func (t *Tgbot) SendBackupToAdmins() {
	if !t.IsRunning() {
		return
	}
	for _, adminId := range adminIds {
		t.sendBackup(int64(adminId))
	}
}

func (t *Tgbot) sendExhaustedToAdmins() {
	if !t.IsRunning() {
		return
	}
	for _, adminId := range adminIds {
		t.getExhausted(int64(adminId))
	}
}

func (t *Tgbot) getServerUsage(chatId int64, messageID ...int) string {
	info := t.prepareServerUsageInfo()

	keyboard := tu.InlineKeyboard(tu.InlineKeyboardRow(
		tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.refresh")).WithCallbackData(t.encodeQuery("usage_refresh"))))

	if len(messageID) > 0 {
		t.editMessageTgBot(chatId, messageID[0], info, keyboard)
	} else {
		t.SendMsgToTgbot(chatId, info, keyboard)
	}

	return info
}

// Send server usage without an inline keyboard
func (t *Tgbot) sendServerUsage() string {
	info := t.prepareServerUsageInfo()
	return info
}

func (t *Tgbot) prepareServerUsageInfo() string {
	info, ipv4, ipv6 := "", "", ""

	// get latest status of server
	t.lastStatus = t.serverService.GetStatus(t.lastStatus)
	onlines := p.GetOnlineClients()

	info += t.I18nBot("tgbot.messages.hostname", "Hostname=="+hostname)
	info += t.I18nBot("tgbot.messages.version", "Version=="+config.GetVersion())
	info += t.I18nBot("tgbot.messages.xrayVersion", "XrayVersion=="+fmt.Sprint(t.lastStatus.Xray.Version))

	// get ip address
	netInterfaces, err := net.Interfaces()
	if err != nil {
		logger.Error("net.Interfaces failed, err: ", err.Error())
		info += t.I18nBot("tgbot.messages.ip", "IP=="+t.I18nBot("tgbot.unknown"))
		info += "\r\n"
	} else {
		for i := 0; i < len(netInterfaces); i++ {
			if (netInterfaces[i].Flags & net.FlagUp) != 0 {
				addrs, _ := netInterfaces[i].Addrs()

				for _, address := range addrs {
					if ipnet, ok := address.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
						if ipnet.IP.To4() != nil {
							ipv4 += ipnet.IP.String() + " "
						} else if ipnet.IP.To16() != nil && !ipnet.IP.IsLinkLocalUnicast() {
							ipv6 += ipnet.IP.String() + " "
						}
					}
				}
			}
		}

		info += t.I18nBot("tgbot.messages.ipv4", "IPv4=="+ipv4)
		info += t.I18nBot("tgbot.messages.ipv6", "IPv6=="+ipv6)
	}

	info += t.I18nBot("tgbot.messages.serverUpTime", "UpTime=="+strconv.FormatUint(t.lastStatus.Uptime/86400, 10), "Unit=="+t.I18nBot("tgbot.days"))
	info += t.I18nBot("tgbot.messages.serverLoad", "Load1=="+strconv.FormatFloat(t.lastStatus.Loads[0], 'f', 2, 64), "Load2=="+strconv.FormatFloat(t.lastStatus.Loads[1], 'f', 2, 64), "Load3=="+strconv.FormatFloat(t.lastStatus.Loads[2], 'f', 2, 64))
	info += t.I18nBot("tgbot.messages.serverMemory", "Current=="+common.FormatTraffic(int64(t.lastStatus.Mem.Current)), "Total=="+common.FormatTraffic(int64(t.lastStatus.Mem.Total)))
	info += t.I18nBot("tgbot.messages.onlinesCount", "Count=="+fmt.Sprint(len(onlines)))
	info += t.I18nBot("tgbot.messages.tcpCount", "Count=="+strconv.Itoa(t.lastStatus.TcpCount))
	info += t.I18nBot("tgbot.messages.udpCount", "Count=="+strconv.Itoa(t.lastStatus.UdpCount))
	info += t.I18nBot("tgbot.messages.traffic", "Total=="+common.FormatTraffic(int64(t.lastStatus.NetTraffic.Sent+t.lastStatus.NetTraffic.Recv)), "Upload=="+common.FormatTraffic(int64(t.lastStatus.NetTraffic.Sent)), "Download=="+common.FormatTraffic(int64(t.lastStatus.NetTraffic.Recv)))
	info += t.I18nBot("tgbot.messages.xrayStatus", "State=="+fmt.Sprint(t.lastStatus.Xray.State))
	return info
}

func (t *Tgbot) UserLoginNotify(username string, password string, ip string, time string, status LoginStatus) {
	if !t.IsRunning() {
		return
	}

	if username == "" || ip == "" || time == "" {
		logger.Warning("UserLoginNotify failed, invalid info!")
		return
	}

	loginNotifyEnabled, err := t.settingService.GetTgBotLoginNotify()
	if err != nil || !loginNotifyEnabled {
		return
	}

	msg := ""
	switch status {
	case LoginSuccess:
		msg += t.I18nBot("tgbot.messages.loginSuccess")
		msg += t.I18nBot("tgbot.messages.hostname", "Hostname=="+hostname)
	case LoginFail:
		msg += t.I18nBot("tgbot.messages.loginFailed")
		msg += t.I18nBot("tgbot.messages.hostname", "Hostname=="+hostname)
		msg += t.I18nBot("tgbot.messages.password", "Password=="+password)
	}
	msg += t.I18nBot("tgbot.messages.username", "Username=="+username)
	msg += t.I18nBot("tgbot.messages.ip", "IP=="+ip)
	msg += t.I18nBot("tgbot.messages.time", "Time=="+time)
	t.SendMsgToTgbotAdmins(msg)
}

func (t *Tgbot) getInboundUsages() string {
	info := ""
	// get traffic
	inbounds, err := t.inboundService.GetAllInbounds()
	if err != nil {
		logger.Warning("GetAllInbounds run failed:", err)
		info += t.I18nBot("tgbot.answers.getInboundsFailed")
	} else {
		// NOTE:If there no any sessions here,need to notify here
		// TODO:Sub-node push, automatic conversion format
		for _, inbound := range inbounds {
			info += t.I18nBot("tgbot.messages.inbound", "Remark=="+inbound.Remark)
			info += t.I18nBot("tgbot.messages.port", "Port=="+strconv.Itoa(inbound.Port))
			info += t.I18nBot("tgbot.messages.traffic", "Total=="+common.FormatTraffic((inbound.Up+inbound.Down)), "Upload=="+common.FormatTraffic(inbound.Up), "Download=="+common.FormatTraffic(inbound.Down))

			if inbound.ExpiryTime == 0 {
				info += t.I18nBot("tgbot.messages.expire", "Time=="+t.I18nBot("tgbot.unlimited"))
			} else {
				info += t.I18nBot("tgbot.messages.expire", "Time=="+time.Unix((inbound.ExpiryTime/1000), 0).Format("2006-01-02 15:04:05"))
			}
			info += "\r\n"
		}
	}
	return info
}
func (t *Tgbot) getInbounds() (*telego.InlineKeyboardMarkup, error) {
	inbounds, err := t.inboundService.GetAllInbounds()
	if err != nil {
		logger.Warning("GetAllInbounds run failed:", err)
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}

	if len(inbounds) == 0 {
		logger.Warning("No inbounds found")
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}

	var buttons []telego.InlineKeyboardButton
	for _, inbound := range inbounds {
		status := "❌"
		if inbound.Enable {
			status = "✅"
		}
		callbackData := t.encodeQuery(fmt.Sprintf("%s %d", "get_clients", inbound.Id))
		buttons = append(buttons, tu.InlineKeyboardButton(fmt.Sprintf("%v - %v", inbound.Remark, status)).WithCallbackData(callbackData))
	}

	cols := 1
	if len(buttons) >= 6 {
		cols = 2
	}

	keyboard := tu.InlineKeyboardGrid(tu.InlineKeyboardCols(cols, buttons...))
	return keyboard, nil
}

func (t *Tgbot) getInboundsAddClient() (*telego.InlineKeyboardMarkup, error) {
	inbounds, err := t.inboundService.GetAllInbounds()
	if err != nil {
		logger.Warning("GetAllInbounds run failed:", err)
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}

	if len(inbounds) == 0 {
		logger.Warning("No inbounds found")
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}

	excludedProtocols := map[model.Protocol]bool{
		model.Tunnel:    true,
		model.Socks:     true,
		model.WireGuard: true,
		model.HTTP:      true,
	}

	var buttons []telego.InlineKeyboardButton
	for _, inbound := range inbounds {
		if excludedProtocols[inbound.Protocol] {
			continue
		}

		status := "❌"
		if inbound.Enable {
			status = "✅"
		}
		callbackData := t.encodeQuery(fmt.Sprintf("%s %d", "add_client_to", inbound.Id))
		buttons = append(buttons, tu.InlineKeyboardButton(fmt.Sprintf("%v - %v", inbound.Remark, status)).WithCallbackData(callbackData))
	}

	cols := 1
	if len(buttons) >= 6 {
		cols = 2
	}

	keyboard := tu.InlineKeyboardGrid(tu.InlineKeyboardCols(cols, buttons...))
	return keyboard, nil
}

func (t *Tgbot) getInboundClients(id int) (*telego.InlineKeyboardMarkup, error) {
	inbound, err := t.inboundService.GetInbound(id)
	if err != nil {
		logger.Warning("getIboundClients run failed:", err)
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	}
	clients, err := t.inboundService.GetClients(inbound)
	var buttons []telego.InlineKeyboardButton

	if err != nil {
		logger.Warning("GetInboundClients run failed:", err)
		return nil, errors.New(t.I18nBot("tgbot.answers.getInboundsFailed"))
	} else {
		if len(clients) > 0 {
			for _, client := range clients {
				buttons = append(buttons, tu.InlineKeyboardButton(client.Email).WithCallbackData(t.encodeQuery("client_get_usage "+client.Email)))
			}

		} else {
			return nil, errors.New(t.I18nBot("tgbot.answers.getClientsFailed"))
		}

	}
	cols := 0
	if len(buttons) < 6 {
		cols = 3
	} else {
		cols = 2
	}
	keyboard := tu.InlineKeyboardGrid(tu.InlineKeyboardCols(cols, buttons...))

	return keyboard, nil
}

func (t *Tgbot) clientInfoMsg(
	traffic *xray.ClientTraffic,
	printEnabled bool,
	printOnline bool,
	printActive bool,
	printDate bool,
	printTraffic bool,
	printRefreshed bool,
) string {
	now := time.Now().Unix()
	expiryTime := ""
	flag := false
	diff := traffic.ExpiryTime/1000 - now
	if traffic.ExpiryTime == 0 {
		expiryTime = t.I18nBot("tgbot.unlimited")
	} else if diff > 172800 || !traffic.Enable {
		expiryTime = time.Unix((traffic.ExpiryTime / 1000), 0).Format("2006-01-02 15:04:05")
		if diff > 0 {
			days := diff / 86400
			hours := (diff % 86400) / 3600
			minutes := (diff % 3600) / 60
			remainingTime := ""
			if days > 0 {
				remainingTime += fmt.Sprintf("%d %s ", days, t.I18nBot("tgbot.days"))
			}
			if hours > 0 {
				remainingTime += fmt.Sprintf("%d %s ", hours, t.I18nBot("tgbot.hours"))
			}
			if minutes > 0 {
				remainingTime += fmt.Sprintf("%d %s", minutes, t.I18nBot("tgbot.minutes"))
			}
			expiryTime += fmt.Sprintf(" (%s)", remainingTime)
		}
	} else if traffic.ExpiryTime < 0 {
		expiryTime = fmt.Sprintf("%d %s", traffic.ExpiryTime/-86400000, t.I18nBot("tgbot.days"))
		flag = true
	} else {
		expiryTime = fmt.Sprintf("%d %s", diff/3600, t.I18nBot("tgbot.hours"))
		flag = true
	}

	total := ""
	if traffic.Total == 0 {
		total = t.I18nBot("tgbot.unlimited")
	} else {
		total = common.FormatTraffic((traffic.Total))
	}

	enabled := ""
	isEnabled, err := t.inboundService.checkIsEnabledByEmail(traffic.Email)
	if err != nil {
		logger.Warning(err)
		enabled = t.I18nBot("tgbot.wentWrong")
	} else if isEnabled {
		enabled = t.I18nBot("tgbot.messages.yes")
	} else {
		enabled = t.I18nBot("tgbot.messages.no")
	}

	active := ""
	if traffic.Enable {
		active = t.I18nBot("tgbot.messages.yes")
	} else {
		active = t.I18nBot("tgbot.messages.no")
	}

	status := t.I18nBot("tgbot.offline")
	if p.IsRunning() {
		for _, online := range p.GetOnlineClients() {
			if online == traffic.Email {
				status = t.I18nBot("tgbot.online")
				break
			}
		}
	}

	output := ""
	output += t.I18nBot("tgbot.messages.email", "Email=="+traffic.Email)
	if printEnabled {
		output += t.I18nBot("tgbot.messages.enabled", "Enable=="+enabled)
	}
	if printOnline {
		output += t.I18nBot("tgbot.messages.online", "Status=="+status)
	}
	if printActive {
		output += t.I18nBot("tgbot.messages.active", "Enable=="+active)
	}
	if printDate {
		if flag {
			output += t.I18nBot("tgbot.messages.expireIn", "Time=="+expiryTime)
		} else {
			output += t.I18nBot("tgbot.messages.expire", "Time=="+expiryTime)
		}
	}
	if printTraffic {
		output += t.I18nBot("tgbot.messages.upload", "Upload=="+common.FormatTraffic(traffic.Up))
		output += t.I18nBot("tgbot.messages.download", "Download=="+common.FormatTraffic(traffic.Down))
		output += t.I18nBot("tgbot.messages.total", "UpDown=="+common.FormatTraffic((traffic.Up+traffic.Down)), "Total=="+total)
	}
	if printRefreshed {
		output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))
	}

	return output
}

func (t *Tgbot) getClientUsage(chatId int64, tgUserID int64, email ...string) {
	traffics, err := t.inboundService.GetClientTrafficTgBot(tgUserID)
	if err != nil {
		logger.Warning(err)
		msg := t.I18nBot("tgbot.wentWrong")
		t.SendMsgToTgbot(chatId, msg)
		return
	}

	if len(traffics) == 0 {
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.answers.askToAddUserId", "TgUserID=="+strconv.FormatInt(tgUserID, 10)))
		return
	}

	output := ""

	if len(traffics) > 0 {
		if len(email) > 0 {
			for _, traffic := range traffics {
				if traffic.Email == email[0] {
					output := t.clientInfoMsg(traffic, true, true, true, true, true, true)
					t.SendMsgToTgbot(chatId, output)
					return
				}
			}
			msg := t.I18nBot("tgbot.noResult")
			t.SendMsgToTgbot(chatId, msg)
			return
		} else {
			for _, traffic := range traffics {
				output += t.clientInfoMsg(traffic, true, true, true, true, true, false)
				output += "\r\n"
			}
		}
	}

	output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))
	t.SendMsgToTgbot(chatId, output)
	output = t.I18nBot("tgbot.commands.pleaseChoose")
	t.SendAnswer(chatId, output, false)
}

func (t *Tgbot) searchClientIps(chatId int64, email string, messageID ...int) {
	ips, err := t.inboundService.GetInboundClientIps(email)
	if err != nil || len(ips) == 0 {
		ips = t.I18nBot("tgbot.noIpRecord")
	}

	output := ""
	output += t.I18nBot("tgbot.messages.email", "Email=="+email)
	output += t.I18nBot("tgbot.messages.ips", "IPs=="+ips)
	output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))

	inlineKeyboard := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.refresh")).WithCallbackData(t.encodeQuery("ips_refresh "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.clearIPs")).WithCallbackData(t.encodeQuery("clear_ips "+email)),
		),
	)

	if len(messageID) > 0 {
		t.editMessageTgBot(chatId, messageID[0], output, inlineKeyboard)
	} else {
		t.SendMsgToTgbot(chatId, output, inlineKeyboard)
	}
}

func (t *Tgbot) clientTelegramUserInfo(chatId int64, email string, messageID ...int) {
	traffic, client, err := t.inboundService.GetClientByEmail(email)
	if err != nil {
		logger.Warning(err)
		msg := t.I18nBot("tgbot.wentWrong")
		t.SendMsgToTgbot(chatId, msg)
		return
	}
	if client == nil {
		msg := t.I18nBot("tgbot.noResult")
		t.SendMsgToTgbot(chatId, msg)
		return
	}
	tgId := "None"
	if client.TgID != 0 {
		tgId = strconv.FormatInt(client.TgID, 10)
	}

	output := ""
	output += t.I18nBot("tgbot.messages.email", "Email=="+email)
	output += t.I18nBot("tgbot.messages.TGUser", "TelegramID=="+tgId)
	output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))

	inlineKeyboard := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.refresh")).WithCallbackData(t.encodeQuery("tgid_refresh "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.removeTGUser")).WithCallbackData(t.encodeQuery("tgid_remove "+email)),
		),
	)

	if len(messageID) > 0 {
		t.editMessageTgBot(chatId, messageID[0], output, inlineKeyboard)
	} else {
		t.SendMsgToTgbot(chatId, output, inlineKeyboard)
		requestUser := telego.KeyboardButtonRequestUsers{
			RequestID: int32(traffic.Id),
			UserIsBot: new(bool),
		}
		keyboard := tu.Keyboard(
			tu.KeyboardRow(
				tu.KeyboardButton(t.I18nBot("tgbot.buttons.selectTGUser")).WithRequestUsers(&requestUser),
			),
			tu.KeyboardRow(
				tu.KeyboardButton(t.I18nBot("tgbot.buttons.closeKeyboard")),
			),
		).WithIsPersistent().WithResizeKeyboard()
		t.SendMsgToTgbot(chatId, t.I18nBot("tgbot.buttons.selectOneTGUser"), keyboard)
	}
}

func (t *Tgbot) searchClient(chatId int64, email string, messageID ...int) {
	traffic, err := t.inboundService.GetClientTrafficByEmail(email)
	if err != nil {
		logger.Warning(err)
		msg := t.I18nBot("tgbot.wentWrong")
		t.SendMsgToTgbot(chatId, msg)
		return
	}
	if traffic == nil {
		msg := t.I18nBot("tgbot.noResult")
		t.SendMsgToTgbot(chatId, msg)
		return
	}

	output := t.clientInfoMsg(traffic, true, true, true, true, true, true)

	inlineKeyboard := tu.InlineKeyboard(
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.refresh")).WithCallbackData(t.encodeQuery("client_refresh "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.resetTraffic")).WithCallbackData(t.encodeQuery("reset_traffic "+email)),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.limitTraffic")).WithCallbackData(t.encodeQuery("limit_traffic "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.resetExpire")).WithCallbackData(t.encodeQuery("reset_exp "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.ipLog")).WithCallbackData(t.encodeQuery("ip_log "+email)),
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.ipLimit")).WithCallbackData(t.encodeQuery("ip_limit "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.setTGUser")).WithCallbackData(t.encodeQuery("tg_user "+email)),
		),
		tu.InlineKeyboardRow(
			tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.toggle")).WithCallbackData(t.encodeQuery("toggle_enable "+email)),
		),
	)
	if len(messageID) > 0 {
		t.editMessageTgBot(chatId, messageID[0], output, inlineKeyboard)
	} else {
		t.SendMsgToTgbot(chatId, output, inlineKeyboard)
	}
}

func (t *Tgbot) addClient(chatId int64, msg string, messageID ...int) {
	inbound, err := t.inboundService.GetInbound(receiver_inbound_ID)
	if err != nil {
		t.SendMsgToTgbot(chatId, err.Error())
		return
	}

	protocol := inbound.Protocol

	switch protocol {
	case model.VMESS, model.VLESS:
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_email")).WithCallbackData("add_client_ch_default_email"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_id")).WithCallbackData("add_client_ch_default_id"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.limitTraffic")).WithCallbackData("add_client_ch_default_traffic"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.resetExpire")).WithCallbackData("add_client_ch_default_exp"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_comment")).WithCallbackData("add_client_ch_default_comment"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.ipLimit")).WithCallbackData("add_client_ch_default_ip_limit"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitDisable")).WithCallbackData("add_client_submit_disable"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitEnable")).WithCallbackData("add_client_submit_enable"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData("add_client_cancel"),
			),
		)
		if len(messageID) > 0 {
			t.editMessageTgBot(chatId, messageID[0], msg, inlineKeyboard)
		} else {
			t.SendMsgToTgbot(chatId, msg, inlineKeyboard)
		}
	case model.Trojan:
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_email")).WithCallbackData("add_client_ch_default_email"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_password")).WithCallbackData("add_client_ch_default_pass_tr"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.limitTraffic")).WithCallbackData("add_client_ch_default_traffic"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.resetExpire")).WithCallbackData("add_client_ch_default_exp"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_comment")).WithCallbackData("add_client_ch_default_comment"),
				tu.InlineKeyboardButton("ip limit").WithCallbackData("add_client_ch_default_ip_limit"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitDisable")).WithCallbackData("add_client_submit_disable"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitEnable")).WithCallbackData("add_client_submit_enable"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData("add_client_cancel"),
			),
		)
		if len(messageID) > 0 {
			t.editMessageTgBot(chatId, messageID[0], msg, inlineKeyboard)
		} else {
			t.SendMsgToTgbot(chatId, msg, inlineKeyboard)
		}
	case model.Shadowsocks:
		inlineKeyboard := tu.InlineKeyboard(
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_email")).WithCallbackData("add_client_ch_default_email"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_password")).WithCallbackData("add_client_ch_default_pass_sh"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.limitTraffic")).WithCallbackData("add_client_ch_default_traffic"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.resetExpire")).WithCallbackData("add_client_ch_default_exp"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.change_comment")).WithCallbackData("add_client_ch_default_comment"),
				tu.InlineKeyboardButton("ip limit").WithCallbackData("add_client_ch_default_ip_limit"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitDisable")).WithCallbackData("add_client_submit_disable"),
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.submitEnable")).WithCallbackData("add_client_submit_enable"),
			),
			tu.InlineKeyboardRow(
				tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.cancel")).WithCallbackData("add_client_cancel"),
			),
		)

		if len(messageID) > 0 {
			t.editMessageTgBot(chatId, messageID[0], msg, inlineKeyboard)
		} else {
			t.SendMsgToTgbot(chatId, msg, inlineKeyboard)
		}
	}

}

func (t *Tgbot) searchInbound(chatId int64, remark string) {
	inbounds, err := t.inboundService.SearchInbounds(remark)
	if err != nil {
		logger.Warning(err)
		msg := t.I18nBot("tgbot.wentWrong")
		t.SendMsgToTgbot(chatId, msg)
		return
	}
	if len(inbounds) == 0 {
		msg := t.I18nBot("tgbot.noInbounds")
		t.SendMsgToTgbot(chatId, msg)
		return
	}

	for _, inbound := range inbounds {
		info := ""
		info += t.I18nBot("tgbot.messages.inbound", "Remark=="+inbound.Remark)
		info += t.I18nBot("tgbot.messages.port", "Port=="+strconv.Itoa(inbound.Port))
		info += t.I18nBot("tgbot.messages.traffic", "Total=="+common.FormatTraffic((inbound.Up+inbound.Down)), "Upload=="+common.FormatTraffic(inbound.Up), "Download=="+common.FormatTraffic(inbound.Down))

		if inbound.ExpiryTime == 0 {
			info += t.I18nBot("tgbot.messages.expire", "Time=="+t.I18nBot("tgbot.unlimited"))
		} else {
			info += t.I18nBot("tgbot.messages.expire", "Time=="+time.Unix((inbound.ExpiryTime/1000), 0).Format("2006-01-02 15:04:05"))
		}
		t.SendMsgToTgbot(chatId, info)

		if len(inbound.ClientStats) > 0 {
			output := ""
			for _, traffic := range inbound.ClientStats {
				output += t.clientInfoMsg(&traffic, true, true, true, true, true, true)
			}
			t.SendMsgToTgbot(chatId, output)
		}
	}
}

func (t *Tgbot) getExhausted(chatId int64) {
	trDiff := int64(0)
	exDiff := int64(0)
	now := time.Now().Unix() * 1000
	var exhaustedInbounds []model.Inbound
	var exhaustedClients []xray.ClientTraffic
	var disabledInbounds []model.Inbound
	var disabledClients []xray.ClientTraffic

	TrafficThreshold, err := t.settingService.GetTrafficDiff()
	if err == nil && TrafficThreshold > 0 {
		trDiff = int64(TrafficThreshold) * 1073741824
	}
	ExpireThreshold, err := t.settingService.GetExpireDiff()
	if err == nil && ExpireThreshold > 0 {
		exDiff = int64(ExpireThreshold) * 86400000
	}
	inbounds, err := t.inboundService.GetAllInbounds()
	if err != nil {
		logger.Warning("Unable to load Inbounds", err)
	}

	for _, inbound := range inbounds {
		if inbound.Enable {
			if (inbound.ExpiryTime > 0 && (inbound.ExpiryTime-now < exDiff)) ||
				(inbound.Total > 0 && (inbound.Total-(inbound.Up+inbound.Down) < trDiff)) {
				exhaustedInbounds = append(exhaustedInbounds, *inbound)
			}
			if len(inbound.ClientStats) > 0 {
				for _, client := range inbound.ClientStats {
					if client.Enable {
						if (client.ExpiryTime > 0 && (client.ExpiryTime-now < exDiff)) ||
							(client.Total > 0 && (client.Total-(client.Up+client.Down) < trDiff)) {
							exhaustedClients = append(exhaustedClients, client)
						}
					} else {
						disabledClients = append(disabledClients, client)
					}
				}
			}
		} else {
			disabledInbounds = append(disabledInbounds, *inbound)
		}
	}

	// Inbounds
	output := ""
	output += t.I18nBot("tgbot.messages.exhaustedCount", "Type=="+t.I18nBot("tgbot.inbounds"))
	output += t.I18nBot("tgbot.messages.disabled", "Disabled=="+strconv.Itoa(len(disabledInbounds)))
	output += t.I18nBot("tgbot.messages.depleteSoon", "Deplete=="+strconv.Itoa(len(exhaustedInbounds)))

	if len(exhaustedInbounds) > 0 {
		output += t.I18nBot("tgbot.messages.depleteSoon", "Deplete=="+t.I18nBot("tgbot.inbounds"))

		for _, inbound := range exhaustedInbounds {
			output += t.I18nBot("tgbot.messages.inbound", "Remark=="+inbound.Remark)
			output += t.I18nBot("tgbot.messages.port", "Port=="+strconv.Itoa(inbound.Port))
			output += t.I18nBot("tgbot.messages.traffic", "Total=="+common.FormatTraffic((inbound.Up+inbound.Down)), "Upload=="+common.FormatTraffic(inbound.Up), "Download=="+common.FormatTraffic(inbound.Down))
			if inbound.ExpiryTime == 0 {
				output += t.I18nBot("tgbot.messages.expire", "Time=="+t.I18nBot("tgbot.unlimited"))
			} else {
				output += t.I18nBot("tgbot.messages.expire", "Time=="+time.Unix((inbound.ExpiryTime/1000), 0).Format("2006-01-02 15:04:05"))
			}
			output += "\r\n"
		}
	}

	// Clients
	exhaustedCC := len(exhaustedClients)
	output += t.I18nBot("tgbot.messages.exhaustedCount", "Type=="+t.I18nBot("tgbot.clients"))
	output += t.I18nBot("tgbot.messages.disabled", "Disabled=="+strconv.Itoa(len(disabledClients)))
	output += t.I18nBot("tgbot.messages.depleteSoon", "Deplete=="+strconv.Itoa(exhaustedCC))

	if exhaustedCC > 0 {
		output += t.I18nBot("tgbot.messages.depleteSoon", "Deplete=="+t.I18nBot("tgbot.clients"))
		var buttons []telego.InlineKeyboardButton
		for _, traffic := range exhaustedClients {
			output += t.clientInfoMsg(&traffic, true, false, false, true, true, false)
			output += "\r\n"
			buttons = append(buttons, tu.InlineKeyboardButton(traffic.Email).WithCallbackData(t.encodeQuery("client_get_usage "+traffic.Email)))
		}
		cols := 0
		if exhaustedCC < 11 {
			cols = 1
		} else {
			cols = 2
		}
		output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))
		keyboard := tu.InlineKeyboardGrid(tu.InlineKeyboardCols(cols, buttons...))
		t.SendMsgToTgbot(chatId, output, keyboard)
	} else {
		output += t.I18nBot("tgbot.messages.refreshedOn", "Time=="+time.Now().Format("2006-01-02 15:04:05"))
		t.SendMsgToTgbot(chatId, output)
	}
}

func (t *Tgbot) notifyExhausted() {
	trDiff := int64(0)
	exDiff := int64(0)
	now := time.Now().Unix() * 1000

	TrafficThreshold, err := t.settingService.GetTrafficDiff()
	if err == nil && TrafficThreshold > 0 {
		trDiff = int64(TrafficThreshold) * 1073741824
	}
	ExpireThreshold, err := t.settingService.GetExpireDiff()
	if err == nil && ExpireThreshold > 0 {
		exDiff = int64(ExpireThreshold) * 86400000
	}
	inbounds, err := t.inboundService.GetAllInbounds()
	if err != nil {
		logger.Warning("Unable to load Inbounds", err)
	}

	var chatIDsDone []int64
	for _, inbound := range inbounds {
		if inbound.Enable {
			if len(inbound.ClientStats) > 0 {
				clients, err := t.inboundService.GetClients(inbound)
				if err == nil {
					for _, client := range clients {
						if client.TgID != 0 {
							chatID := client.TgID
							if !int64Contains(chatIDsDone, chatID) && !checkAdmin(chatID) {
								var disabledClients []xray.ClientTraffic
								var exhaustedClients []xray.ClientTraffic
								traffics, err := t.inboundService.GetClientTrafficTgBot(client.TgID)
								if err == nil && len(traffics) > 0 {
									output := t.I18nBot("tgbot.messages.exhaustedCount", "Type=="+t.I18nBot("tgbot.clients"))
									for _, traffic := range traffics {
										if traffic.Enable {
											if (traffic.ExpiryTime > 0 && (traffic.ExpiryTime-now < exDiff)) ||
												(traffic.Total > 0 && (traffic.Total-(traffic.Up+traffic.Down) < trDiff)) {
												exhaustedClients = append(exhaustedClients, *traffic)
											}
										} else {
											disabledClients = append(disabledClients, *traffic)
										}
									}
									if len(exhaustedClients) > 0 {
										output += t.I18nBot("tgbot.messages.disabled", "Disabled=="+strconv.Itoa(len(disabledClients)))
										if len(disabledClients) > 0 {
											output += t.I18nBot("tgbot.clients") + ":\r\n"
											for _, traffic := range disabledClients {
												output += " " + traffic.Email
											}
											output += "\r\n"
										}
										output += "\r\n"
										output += t.I18nBot("tgbot.messages.depleteSoon", "Deplete=="+strconv.Itoa(len(exhaustedClients)))
										for _, traffic := range exhaustedClients {
											output += t.clientInfoMsg(&traffic, true, false, false, true, true, false)
											output += "\r\n"
										}
										t.SendMsgToTgbot(chatID, output)
									}
									chatIDsDone = append(chatIDsDone, chatID)
								}
							}
						}
					}
				}
			}
		}
	}
}

func int64Contains(slice []int64, item int64) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func (t *Tgbot) onlineClients(chatId int64, messageID ...int) {
	if !p.IsRunning() {
		return
	}

	onlines := p.GetOnlineClients()
	onlinesCount := len(onlines)
	output := t.I18nBot("tgbot.messages.onlinesCount", "Count=="+fmt.Sprint(onlinesCount))
	keyboard := tu.InlineKeyboard(tu.InlineKeyboardRow(
		tu.InlineKeyboardButton(t.I18nBot("tgbot.buttons.refresh")).WithCallbackData(t.encodeQuery("onlines_refresh"))))

	if onlinesCount > 0 {
		var buttons []telego.InlineKeyboardButton
		for _, online := range onlines {
			buttons = append(buttons, tu.InlineKeyboardButton(online).WithCallbackData(t.encodeQuery("client_get_usage "+online)))
		}
		cols := 0
		if onlinesCount < 21 {
			cols = 2
		} else if onlinesCount < 61 {
			cols = 3
		} else {
			cols = 4
		}
		keyboard.InlineKeyboard = append(keyboard.InlineKeyboard, tu.InlineKeyboardCols(cols, buttons...)...)
	}

	if len(messageID) > 0 {
		t.editMessageTgBot(chatId, messageID[0], output, keyboard)
	} else {
		t.SendMsgToTgbot(chatId, output, keyboard)
	}
}

func (t *Tgbot) sendBackup(chatId int64) {
	output := t.I18nBot("tgbot.messages.backupTime", "Time=="+time.Now().Format("2006-01-02 15:04:05"))
	t.SendMsgToTgbot(chatId, output)

	// Update by manually trigger a checkpoint operation
	err := database.Checkpoint()
	if err != nil {
		logger.Error("Error in trigger a checkpoint operation: ", err)
	}

	file, err := os.Open(config.GetDBPath())
	if err == nil {
		document := tu.Document(
			tu.ID(chatId),
			tu.File(file),
		)
		_, err = bot.SendDocument(context.Background(), document)
		if err != nil {
			logger.Error("Error in uploading backup: ", err)
		}
	} else {
		logger.Error("Error in opening db file for backup: ", err)
	}

	file, err = os.Open(xray.GetConfigPath())
	if err == nil {
		document := tu.Document(
			tu.ID(chatId),
			tu.File(file),
		)
		_, err = bot.SendDocument(context.Background(), document)
		if err != nil {
			logger.Error("Error in uploading config.json: ", err)
		}
	} else {
		logger.Error("Error in opening config.json file for backup: ", err)
	}
}

func (t *Tgbot) sendBanLogs(chatId int64, dt bool) {
	if dt {
		output := t.I18nBot("tgbot.messages.datetime", "DateTime=="+time.Now().Format("2006-01-02 15:04:05"))
		t.SendMsgToTgbot(chatId, output)
	}

	file, err := os.Open(xray.GetIPLimitBannedPrevLogPath())
	if err == nil {
		// Check if the file is non-empty before attempting to upload
		fileInfo, _ := file.Stat()
		if fileInfo.Size() > 0 {
			document := tu.Document(
				tu.ID(chatId),
				tu.File(file),
			)
			_, err = bot.SendDocument(context.Background(), document)
			if err != nil {
				logger.Error("Error in uploading IPLimitBannedPrevLog: ", err)
			}
		} else {
			logger.Warning("IPLimitBannedPrevLog file is empty, not uploading.")
		}
		file.Close()
	} else {
		logger.Error("Error in opening IPLimitBannedPrevLog file for backup: ", err)
	}

	file, err = os.Open(xray.GetIPLimitBannedLogPath())
	if err == nil {
		// Check if the file is non-empty before attempting to upload
		fileInfo, _ := file.Stat()
		if fileInfo.Size() > 0 {
			document := tu.Document(
				tu.ID(chatId),
				tu.File(file),
			)
			_, err = bot.SendDocument(context.Background(), document)
			if err != nil {
				logger.Error("Error in uploading IPLimitBannedLog: ", err)
			}
		} else {
			logger.Warning("IPLimitBannedLog file is empty, not uploading.")
		}
		file.Close()
	} else {
		logger.Error("Error in opening IPLimitBannedLog file for backup: ", err)
	}
}

func (t *Tgbot) sendCallbackAnswerTgBot(id string, message string) {
	params := telego.AnswerCallbackQueryParams{
		CallbackQueryID: id,
		Text:            message,
	}
	if err := bot.AnswerCallbackQuery(context.Background(), &params); err != nil {
		logger.Warning(err)
	}
}

func (t *Tgbot) editMessageCallbackTgBot(chatId int64, messageID int, inlineKeyboard *telego.InlineKeyboardMarkup) {
	params := telego.EditMessageReplyMarkupParams{
		ChatID:      tu.ID(chatId),
		MessageID:   messageID,
		ReplyMarkup: inlineKeyboard,
	}
	if _, err := bot.EditMessageReplyMarkup(context.Background(), &params); err != nil {
		logger.Warning(err)
	}
}

func (t *Tgbot) editMessageTgBot(chatId int64, messageID int, text string, inlineKeyboard ...*telego.InlineKeyboardMarkup) {
	params := telego.EditMessageTextParams{
		ChatID:    tu.ID(chatId),
		MessageID: messageID,
		Text:      text,
		ParseMode: "HTML",
	}
	if len(inlineKeyboard) > 0 {
		params.ReplyMarkup = inlineKeyboard[0]
	}
	if _, err := bot.EditMessageText(context.Background(), &params); err != nil {
		logger.Warning(err)
	}
}

func (t *Tgbot) SendMsgToTgbotDeleteAfter(chatId int64, msg string, delayInSeconds int, replyMarkup ...telego.ReplyMarkup) {
	// Determine if replyMarkup was passed; otherwise, set it to nil
	var replyMarkupParam telego.ReplyMarkup
	if len(replyMarkup) > 0 {
		replyMarkupParam = replyMarkup[0] // Use the first element
	}

	// Send the message
	sentMsg, err := bot.SendMessage(context.Background(), &telego.SendMessageParams{
		ChatID:      tu.ID(chatId),
		Text:        msg,
		ReplyMarkup: replyMarkupParam, // Use the correct replyMarkup value
	})
	if err != nil {
		logger.Warning("Failed to send message:", err)
		return
	}

	// Delete the sent message after the specified number of seconds
	go func() {
		time.Sleep(time.Duration(delayInSeconds) * time.Second) // Wait for the specified delay
		t.deleteMessageTgBot(chatId, sentMsg.MessageID)         // Delete the message
		delete(userStates, chatId)
	}()
}

func (t *Tgbot) deleteMessageTgBot(chatId int64, messageID int) {
	params := telego.DeleteMessageParams{
		ChatID:    tu.ID(chatId),
		MessageID: messageID,
	}
	if err := bot.DeleteMessage(context.Background(), &params); err != nil {
		logger.Warning("Failed to delete message:", err)
	} else {
		logger.Info("Message deleted successfully")
	}
}

func (t *Tgbot) isSingleWord(text string) bool {
	text = strings.TrimSpace(text)
	re := regexp.MustCompile(`\s+`)
	return re.MatchString(text)
}

// 〔中文注释〕: 新增方法，实现 TelegramService 接口。
// 当设备限制任务需要发送消息时，会调用此方法。
// 该方法内部调用了已有的 SendMsgToTgbotAdmins 函数，将消息发送给所有管理员。
func (t *Tgbot) SendMessage(msg string) error {
    if !t.IsRunning() {
        // 〔中文注释〕: 如果 Bot 未运行，返回错误，防止程序出错。
        return errors.New("Telegram bot is not running")
    }
    // 〔中文注释〕: 调用现有方法将消息发送给所有已配置的管理员。
    t.SendMsgToTgbotAdmins(msg)
    return nil
}

// 【新增函数】: 检查并安装【订阅转换】
func (t *Tgbot) checkAndInstallSubconverter(chatId int64) {
	domain, err := t.getDomain()
	if err != nil {
		t.SendMsgToTgbot(chatId, fmt.Sprintf("❌ 操作失败：%v", err))
		return
	}
	subConverterUrl := fmt.Sprintf("https://%s:15268", domain)

	t.SendMsgToTgbot(chatId, fmt.Sprintf("正在检测服务状态...\n地址: `%s`", subConverterUrl))

	go func() {
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}
		client := &http.Client{Transport: tr, Timeout: 3 * time.Second}
		_, err := client.Get(subConverterUrl)

		if err == nil {
			t.SendMsgToTgbot(chatId, fmt.Sprintf("✅ 服务已存在！\n\n您可以直接通过以下地址访问：\n`%s`", subConverterUrl))
		} else {
			confirmKeyboard := tu.InlineKeyboard(
				tu.InlineKeyboardRow(
					tu.InlineKeyboardButton("✅ 是，立即安装").WithCallbackData("confirm_sub_install"),
					tu.InlineKeyboardButton("❌ 否，取消").WithCallbackData("cancel_sub_install"),
				),
			)
			t.SendMsgToTgbot(chatId, "⚠️ 服务检测失败，可能尚未安装。\n\n------>>>>您想现在执行〔订阅转换〕安装指令吗？\n\n**【重要】**请确保服务器防火墙已放行 `8000` 和 `15268` 端口。", confirmKeyboard)
		}
	}()
}

// 【新增辅助函数】: 发送【订阅转换】安装成功的通知
func (t *Tgbot) SendSubconverterSuccess() {
// func (t *Tgbot) SendSubconverterSuccess(targetChatId int64) { 
	domain, err := t.getDomain()
	if err != nil {
		domain = "[您的面板域名]"
	}

	msgText := fmt.Sprintf(
		"🎉 **恭喜！【订阅转换】模块已成功安装！**\n\n"+
			"您现在可以使用以下地址访问 Web 界面：\n\n"+
			"🔗 **登录地址**: `https://%s:15268`\n\n"+
			"默认用户名: `admin`\n"+
			"默认 密码: `123456`\n\n"+
			"可登录订阅转换后台修改您的密码！",
		domain,
	)
	t.SendMsgToTgbotAdmins(msgText)
	// t.SendMsgToTgbot(targetChatId, msgText)
}

// 【新增辅助函数】: 获取域名（shell 方案）
func (t *Tgbot) getDomain() (string, error) {
	cmd := exec.Command("/usr/local/x-ui/x-ui", "setting", "-getCert", "true")
	output, err := cmd.Output()
	if err != nil {
		return "", errors.New("执行命令获取证书路径失败，请确保已为面板配置 SSL 证书")
	}

	lines := strings.Split(string(output), "\n")
	certLine := ""
	for _, line := range lines {
		if strings.HasPrefix(line, "cert:") {
			certLine = line
			break
		}
	}

	if certLine == "" {
		return "", errors.New("无法从 x-ui 命令输出中找到证书路径")
	}

	certPath := strings.TrimSpace(strings.TrimPrefix(certLine, "cert:"))
	if certPath == "" {
		return "", errors.New("证书路径为空，请确保已为面板配置 SSL 证书")
	}

	domain := filepath.Base(filepath.Dir(certPath))
	return domain, nil
}


// 【新增辅助函数】: 随机字符串生成器
func (t *Tgbot) randomString(length int, charset string) string {
	bytes := make([]byte, length)
	for i := range bytes {
		randomIndex, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		bytes[i] = charset[randomIndex.Int64()]
	}
	return string(bytes)
}


func (t *Tgbot) handleCallbackQuery(ctx *th.Context, cq telego.CallbackQuery) error {
    // 1) 确保 Message 可访问 —— 注意必须调用 cq.Message.Message() 而不是直接访问 .Message
    if cq.Message == nil || cq.Message.Message == nil {
        _ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID).WithText("消息对象不存在"))
        return nil
    }

    // 关键修正：这里要调用方法 Message()
    msg := cq.Message.Message()   // <- 调用方法，返回 *telego.Message
    // 现在 msg 是 *telego.Message，可以访问 Chat / MessageID
    chatIDInt64 := msg.Chat.ID
    messageID := msg.MessageID

    // 解码回调数据（沿用你已有函数）
    data, err := t.decodeQuery(cq.Data)
    if err != nil {
        _ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID).WithText("回调数据解析失败"))
        return nil
    }

    // 移除内联键盘（telegoutil 构造 params）
    if _, err := ctx.Bot().EditMessageReplyMarkup(ctx, tu.EditMessageReplyMarkup(tu.ID(chatIDInt64), messageID, nil)); err != nil {
        logger.Warningf("TG Bot: 移除内联键盘失败: %v", err)
    }

    // ---------- oneclick_ 分支 ----------
    if strings.HasPrefix(data, "oneclick_") {
        configType := strings.TrimPrefix(data, "oneclick_")

        var creationMessage string
        switch configType {
        case "reality":
            creationMessage = "🚀 Vless + TCP + Reality + Vision"
        case "xhttp_reality":
            creationMessage = "⚡ Vless + XHTTP + Reality"
        case "tls":
            creationMessage = "🛡️ Vless Encryption + XHTTP + TLS"
		case "switch_vision": // 【新增】: 为占位按钮提供单独的提示
			t.SendMsgToTgbot(chatIDInt64, "此协议组合的功能还在开发中 ............暂不可用...")
			_ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID).WithText("开发中..."))
			return nil
        default:
            creationMessage = strings.ToUpper(configType)
        }

        // 注意：不要把无返回值函数当作表达式使用，直接调用即可
        t.SendMsgToTgbot(chatIDInt64, fmt.Sprintf("🛠️ 正在为您远程创建 %s 配置，请稍候...", creationMessage))
        _ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID).WithText("配置已创建，请查收管理员私信。"))
        return nil
    }

    // ---------- confirm_sub_install 分支 ----------
    if data == "confirm_sub_install" {
        t.SendMsgToTgbot(chatIDInt64, "🛠️ **已接收到订阅转换安装指令，** 后台正在异步执行...")

        if err := t.serverService.InstallSubconverter(); err != nil {
            // 直接调用发送函数（无返回值）
            t.SendMsgToTgbot(chatIDInt64, fmt.Sprintf("❌ **安装指令启动失败：**\n`%v`", err))
        } else {
            t.SendMsgToTgbot(chatIDInt64, "✅ **安装指令已成功发送到后台。**\n\n请等待安装完成的管理员通知。")
        }

        _ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID))
        return nil
    }

    // 默认回答，避免用户界面卡住
    _ = ctx.Bot().AnswerCallbackQuery(ctx, tu.CallbackQuery(cq.ID).WithText("操作已完成。"))
    return nil
}

// 新增一个公共方法 (大写 G) 来包装私有方法
func (t *Tgbot) GetDomain() (string, error) {
    return t.getDomain()
}

// openPortWithUFW 检查/安装 ufw，放行一系列默认端口，并放行指定的端口
func (t *Tgbot) openPortWithUFW(port int) error {
	// 【中文注释】: 将所有 Shell 逻辑整合为一个命令。
	// 新增了对默认端口列表 (22, 80, 443, 13688, 8443) 的放行逻辑。
	shellCommand := fmt.Sprintf(`
	# 定义需要放行的指定端口和一系列默认端口
	PORT_TO_OPEN=%d
	DEFAULT_PORTS="22 80 443 13688 8443"

	echo "脚本开始：准备配置 ufw 防火墙..."

	# 1. 检查/安装 ufw
	if ! command -v ufw &> /dev/null; then
		echo "ufw 防火墙未安装，正在自动安装..."
		# 使用绝对路径执行 apt-get，避免 PATH 问题，并抑制不必要的输出
		DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get update -qq >/dev/null
		DEBIAN_FRONTEND=noninteractive /usr/bin/apt-get install -y -qq ufw >/dev/null
		if [ $? -ne 0 ]; then echo "❌ ufw 安装失败。"; exit 1; fi
		echo "✅ ufw 安装成功。"
	fi

	# 2. 【新增】循环放行所有默认端口
	echo "正在检查并放行基础服务端口: $DEFAULT_PORTS"
	for p in $DEFAULT_PORTS; do
		# 使用静默模式检查规则是否存在，如果不存在则添加
		if ! ufw status | grep -qw "$p/tcp"; then
			echo "端口 $p/tcp 未放行，正在执行 ufw allow $p/tcp..."
			ufw allow $p/tcp >/dev/null
			if [ $? -ne 0 ]; then echo "❌ ufw 端口 $p 放行失败。"; exit 1; fi
		else
			echo "端口 $p/tcp 规则已存在，跳过。"
		fi
	done
	echo "✅ 基础服务端口检查/放行完毕。"

	# 3. 放行指定的端口
	echo "正在为当前【入站配置】放行指定端口 $PORT_TO_OPEN..."
	if ! ufw status | grep -qw "$PORT_TO_OPEN/tcp"; then
		ufw allow $PORT_TO_OPEN/tcp >/dev/null
		if [ $? -ne 0 ]; then echo "❌ ufw 端口 $PORT_TO_OPEN 放行失败。"; exit 1; fi
		echo "✅ 端口 $PORT_TO_OPEN 已成功放行。"
	else
		echo "端口 $PORT_TO_OPEN 规则已存在，跳过。"
	fi
	

	# 4. 检查/激活防火墙
	if ! ufw status | grep -q "Status: active"; then
		echo "ufw 状态：未激活。正在强制激活..."
		# --force 选项可以无需交互直接激活
		ufw --force enable
		if [ $? -ne 0 ]; then echo "❌ ufw 激活失败。"; exit 1; fi
		echo "✅ ufw 已成功激活。"
	else
		echo "ufw 状态已经是激活状态。"
	fi

	echo "🎉 所有防火墙配置已完成。"

	`, port) // 将函数传入的 port 参数填充到 Shell 脚本中

	// 使用 exec.CommandContext 运行完整的 shell 脚本
	cmd := exec.CommandContext(context.Background(), "/bin/bash", "-c", shellCommand)
	
	// 捕获命令的标准输出和标准错误
	output, err := cmd.CombinedOutput()
	
	// 无论成功与否，都记录完整的 Shell 执行日志，便于调试
	logOutput := string(output)
	logger.Infof("执行 ufw 端口放行脚本（目标端口 %d）的完整输出：\n%s", port, logOutput)

	if err != nil {
		// 如果脚本执行出错 (例如 exit 1)，则返回包含详细输出的错误信息
		return fmt.Errorf("执行 ufw 端口放行脚本时发生错误: %v, Shell 输出: %s", err, logOutput)
	}

    return nil
}

// =========================================================================================
// 【核心数据结构：XML 解析专用】
// =========================================================================================

// 〔中文注释〕: 内部通用的新闻数据结构，用于避免类型不匹配错误。
type NewsItem struct {
	Title       string
	Description string // 用于链接或 GitHub 描述
}

// 用于解析 Google News 或通用 RSS 格式
type RssFeed struct {
	XMLName xml.Name   `xml:"rss"`
	Channel RssChannel `xml:"channel"`
}

type RssChannel struct {
	Title string    `xml:"title"`
	Items []RssItem `xml:"item"`
}

type RssItem struct {
	Title string `xml:"title"`
	Link  string `xml:"link"`
}

// 用于解析 YouTube 官方 Atom Feed 格式
type AtomFeed struct {
	XMLName xml.Name    `xml:"feed"`
	Entries []AtomEntry `xml:"entry"`
}

type AtomEntry struct {
	Title string `xml:"title"`
	Link  struct {
		Href string `xml:"href,attr"`
	} `xml:"link"`
}

// 〔中文注释〕: 内部辅助函数：生成一个安全的随机数。
func safeRandomInt(max int) int {
	if max <= 0 {
		return 0
	}
	result, err := rand.Int(rand.Reader, big.NewInt(int64(max)))
	if err != nil {
		return time.Now().Nanosecond() % max
	}
	return int(result.Int64())
}

// =========================================================================================
// 【辅助函数：每日一语】 (最终修复：严格遵循官方文档 Token 机制，增强健壮性)
// =========================================================================================

// 〔中文注释〕: 辅助函数：获取完整的古诗词。严格遵循官方 Token 文档，确保稳定性。
func (t *Tgbot) getDailyVerse() (string, error) {
	client := &http.Client{Timeout: 8 * time.Second}

	// 1. 获取 Token
	tokenResp, err := client.Get("https://v2.jinrishici.com/token")
	if err != nil {
		return "", fmt.Errorf("步骤 1: 请求 Token API 失败: %v", err)
	}
	defer tokenResp.Body.Close()

	tokenBody, err := ioutil.ReadAll(tokenResp.Body)
	if err != nil {
		return "", fmt.Errorf("步骤 1: 读取 Token 响应失败: %v", err)
	}

	var tokenResult struct {
		Status string `json:"status"`
		Token  string `json:"data"`
	}

	if json.Unmarshal(tokenBody, &tokenResult) != nil || tokenResult.Status != "success" || tokenResult.Token == "" {
		return "", fmt.Errorf("步骤 1: 解析 Token JSON 失败或状态异常: %s", string(tokenBody))
	}

	// 2. 使用 Token 获取诗句
	sentenceURL := "https://v2.jinrishici.com/sentence" // 简化 URL
	req, err := http.NewRequest("GET", sentenceURL, nil)
	if err != nil {
		return "", fmt.Errorf("步骤 2: 创建请求失败: %v", err)
	}
	// 严格按照文档，将 Token 放在 X-User-Token Header 中
	req.Header.Add("X-User-Token", tokenResult.Token)
	// 增加 User-Agent 伪装成浏览器请求
	req.Header.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

	sentenceResp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("步骤 2: 请求诗句 API 失败: %v", err)
	}
	defer sentenceResp.Body.Close()

	sentenceBody, err := ioutil.ReadAll(sentenceResp.Body)
	if err != nil {
		return "", fmt.Errorf("步骤 2: 读取诗句响应失败: %v", err)
	}

	var result struct {
		Status string `json:"status"`
		Data   struct {
			Content string `json:"content"`
			Origin  struct {
				Title  string `json:"title"`
				Author string `json:"author"`
			} `json:"origin"`
		} `json:"data"`
	}

	if json.Unmarshal(sentenceBody, &result) != nil || result.Status != "success" || result.Data.Content == "" {
		// 如果失败，记录完整的 JSON 响应，便于调试
		return "", fmt.Errorf("步骤 2: 解析诗句 JSON 失败或内容为空。返回状态码: %d, 响应体: %s", sentenceResp.StatusCode, string(sentenceBody))
	}

	poemContent := strings.ReplaceAll(result.Data.Content, "，", "，\n")
	return fmt.Sprintf("📜 **【每日一语】**\n\n%s\n\n`—— %s ·《%s》`", poemContent, result.Data.Origin.Author, result.Data.Origin.Title), nil
}

// =========================================================================================
// 【辅助函数：图片发送】 (随机打乱 + 冗余尝试 + 播种修复)
// =========================================================================================

// 〔中文注释〕: 【最终重构】图片发送函数：按随机顺序尝试3个不同的图片源。
func (t *Tgbot) sendRandomImageWithFallback() {

	// 强制使用动态种子，确保每次调用时随机序列都不同
	r := rng.New(rng.NewSource(time.Now().UnixNano()))

	// 定义所有可用的图片源及其标题
	imageSources := []struct {
		Name    string
		API     string
		Caption string
	}{
		{
			Name:    "waifu.pics (动漫/科技)",
			API:     "https://api.waifu.pics/sfw/waifu",
			Caption: "🖼️ **【今日美图】**\n（来源：waifu.pics 动漫）",
		},
		{
			Name: "Picsum Photos (唯美风景)",
			// Picsum 获取图片列表，随机选择一张。r.Intn(10)+1 用于随机选择页码。
			API:     fmt.Sprintf("https://picsum.photos/v2/list?page=%d&limit=100", r.Intn(10)+1),
			Caption: "🏞️ **【今日美图】**\n（来源：Picsum Photos 唯美风景）",
		},
		{
			Name:    "Bing 每日图片 (高清/自然)",
			API:     "https://api.adicw.cn/api/images/bing",
			Caption: "🌄 **【今日美图】**\n（来源：Bing 每日图片）",
		},
	}

	// 随机打乱数组顺序
	sourceCount := len(imageSources)
	for i := sourceCount - 1; i > 0; i-- {
		j := r.Intn(i + 1)
		imageSources[i], imageSources[j] = imageSources[j], imageSources[i]
	}

	var imageURL string
	var caption string
	var found bool

	// 逐个尝试所有来源，直到成功
	for i, source := range imageSources {
		logger.Infof("图片获取：开始尝试来源 (随机顺序 [%d/%d]): %s", i+1, len(imageSources), source.Name)

		tempURL, err := t.fetchImageFromAPI(source.API, source.Name)

		if err == nil && tempURL != "" {
			imageURL = tempURL
			caption = source.Caption
			found = true
			// 日志直接使用 source.Name
			logger.Infof("图片获取：来源 [%s] 成功，URL: %s", source.Name, imageURL)
			break // 找到一个成功的就退出循环
		}
		logger.Warningf("图片来源 [%s] 尝试失败: %v", source.Name, err)
	}

	if !found {
		logger.Warning("所有图片来源均失败，跳过图片发送。")
		return
	}

	// --- SEND_IMAGE 逻辑 ---
	// 假设 bot 和 adminIds 是可用的全局或结构体变量
	for _, adminId := range adminIds {
		photo := tu.Photo(
			tu.ID(adminId),
			tu.FileFromURL(imageURL),
		).WithCaption(caption).WithParseMode(telego.ModeMarkdown)

		_, err := bot.SendPhoto(context.Background(), photo)
		if err != nil {
			logger.Warningf("发送图片给管理员 %d 失败: %v", adminId, err)
		}
		time.Sleep(300 * time.Millisecond)
	}
}

// =========================================================================================
// 【新的辅助函数：封装图片获取逻辑】 (用于清理 sendRandomImageWithFallback 函数体)
// =========================================================================================

// 〔中文注释〕: 辅助函数：根据不同的 API 逻辑获取图片 URL。
func (t *Tgbot) fetchImageFromAPI(apiURL string, sourceName string) (string, error) {
	client := &http.Client{
		Timeout: 15 * time.Second,
		// 确保 client 遵循重定向
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			return nil
		},
	}

	// 伪装 User-Agent
	req, err := http.NewRequest("GET", apiURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusFound && resp.StatusCode != http.StatusSeeOther {
		return "", fmt.Errorf("API 返回非 200/302 状态码: %d", resp.StatusCode)
	}

	if strings.Contains(sourceName, "waifu.pics") {
		// waifu.pics (JSON API)
		body, _ := ioutil.ReadAll(resp.Body)
		var res struct{ URL string `json:"url"` }
		if json.Unmarshal(body, &res) == nil && res.URL != "" {
			return res.URL, nil
		}
		return "", errors.New("waifu.pics JSON 解析失败")
	} else if strings.Contains(sourceName, "Picsum Photos") {
		// Picsum Photos (列表 JSON API)
		body, _ := ioutil.ReadAll(resp.Body)
		var list []struct{ ID string `json:"id"` }
		if json.Unmarshal(body, &list) == nil && len(list) > 0 {
			// 这里我们不能使用 safeRandomInt，因为 safeRandomInt 也在依赖 rng
			// 我们需要使用一个新的随机源或者将 r 传入
			// 为了简化，这里直接返回一个固定的格式化URL，让用户看到 Picsum 的图
			return fmt.Sprintf("https://picsum.photos/id/%s/1024/768", list[0].ID), nil
		}
		return "", errors.New("Picsum Photos 列表解析失败或列表为空")
	} else if strings.Contains(sourceName, "Bing 每日图片") {
		// Bing 每日图片 (重定向或直接图片 URL)
		// 检查是否有重定向（例如 Unsplash, Bing）
		if resp.Request.URL.String() != apiURL {
			return resp.Request.URL.String(), nil
		}
		// 如果 API 返回的是 200，但其响应体内容就是图片数据，
		// 我们可以返回原始 URL，让 Telegram 自己处理。
		return apiURL, nil
	}

	return "", errors.New("未知图片源处理逻辑")
}

// =========================================================================================
// 【辅助函数：新闻资讯核心抓取逻辑】 (已重构，逻辑更清晰)
// =========================================================================================

// 【中文注释】: 新闻源的数据结构，增加 Type 字段用于区分解析方式
type NewsSource struct {
	Name string
	API  string
	Type string // "RSS2JSON" 或 "DirectJSON"
}


// 〔中文注释〕: 辅助函数：核心逻辑，从给定的 API 获取新闻简报。
// 此函数现在依赖传入的 source.Type 来决定如何解析数据，不再使用模糊的字符串匹配。
func fetchNewsFromGlobalAPI(source NewsSource, limit int) (string, error) {
	client := &http.Client{Timeout: 15 * time.Second}
	var newsItems []NewsItem
	var err error

	// --- 步骤 1: 发起网络请求 ---
	req, reqErr := http.NewRequest("GET", source.API, nil)
	if reqErr != nil {
		return "", fmt.Errorf("创建请求失败: %v", reqErr)
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")

	resp, respErr := client.Do(req)
	if respErr != nil {
		return "", fmt.Errorf("请求 %s API 失败: %v", source.Name, respErr)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("请求 %s API 返回非 200 状态码: %d", source.Name, resp.StatusCode)
	}

	body, readErr := ioutil.ReadAll(resp.Body)
	if readErr != nil {
		return "", fmt.Errorf("读取 %s 响应失败: %v", source.Name, readErr)
	}

	// --- 步骤 2: 根据来源类型解析响应 ---
	switch source.Type {
	case "RSS2JSON":
		// 【修复】: 专门处理来自 api.rss2json.com 的数据，适用于 YouTube, Google News 和新的币圈新闻源
		var result struct {
			Status string `json:"status"`
			Items  []struct {
				Title string `json:"title"`
				Link  string `json:"link"`
			} `json:"items"`
		}
		if jsonErr := json.Unmarshal(body, &result); jsonErr == nil && result.Status == "ok" {
			for _, item := range result.Items {
				newsItems = append(newsItems, NewsItem{
					Title:       item.Title,
					Description: item.Link,
				})
			}
		} else {
			err = fmt.Errorf("解析 %s 的 RSS2JSON 响应失败: %v。响应体: %s", source.Name, jsonErr, string(body))
		}

	case "DirectJSON":
		// 【保留】: 处理直接返回 JSON 的 API，例如 GitHub Trending
		if strings.Contains(source.Name, "GitHub") {
			var result []struct {
				RepoName string `json:"repo_name"`
				Desc     string `json:"desc"`
			}
			if jsonErr := json.Unmarshal(body, &result); jsonErr == nil {
				for _, item := range result {
					newsItems = append(newsItems, NewsItem{
						Title:       fmt.Sprintf("⭐ %s", item.RepoName),
						Description: item.Desc,
					})
				}
			} else {
				err = fmt.Errorf("解析 GitHub Trending JSON 失败: %v", jsonErr)
			}
		}
		// 这里可以为其他 DirectJSON 类型的源添加更多的 else if
	default:
		err = fmt.Errorf("未知的源类型: %s", source.Type)
	}

	if err != nil {
		return "", err
	}

	if len(newsItems) == 0 {
		return "", errors.New(source.Name + " 简报内容为空")
	}

	// --- 步骤 3: 最终消息构建 ---
	var builder strings.Builder
	builder.WriteString(fmt.Sprintf("📰 **【%s 简报】**\n", source.Name))

	for i, item := range newsItems {
		if i >= limit {
			break
		}
		if item.Title != "" {
			// 移除 RSS 源标题中可能包含的来源信息，让内容更整洁
			cleanTitle := strings.ReplaceAll(item.Title, " - YouTube", "")
			// 移除 HTML 标签（RSS/Atom Title中常见）
			cleanTitle = regexp.MustCompile("<[^>]*>").ReplaceAllString(cleanTitle, "")
			// 对 Google News 的标题做特殊清理
			if strings.Contains(source.Name, "Google News") {
				parts := strings.Split(cleanTitle, " - ")
				if len(parts) > 1 {
					cleanTitle = strings.Join(parts[:len(parts)-1], " - ")
				}
			}

			// 【排版修复】: 使用 \n%d. %s 开始新的一条新闻
			builder.WriteString(fmt.Sprintf("\n%d. %s", i+1, cleanTitle))

			// 链接/描述只有在特定源时才显示
			if item.Description != "" && (source.Type == "RSS2JSON" || strings.Contains(source.Name, "GitHub")) {
				builder.WriteString(fmt.Sprintf("\n  `%s`", item.Description))
			}

			// 【排版修复】: 在每条新闻项的末尾添加额外的空行，确保分隔清晰
			builder.WriteString("\n")
		}
	}

	return builder.String(), nil
}


// =========================================================================================
// 【核心函数：getNewsBriefingWithFallback】 (已重构，确保随机性和来源有效性)
// =========================================================================================

// 〔中文注释〕: 【最终重构】新闻资讯获取函数：随机排列源并逐个尝试，直到成功或全部失败。
func (t *Tgbot) getNewsBriefingWithFallback() (string, error) {

	// 强制使用动态种子，确保每次调用时随机序列都不同
	r := rng.New(rng.NewSource(time.Now().UnixNano()))

	// Google News 的 URL 计算
	rssQueryGoogle := url.QueryEscape("AI 科技 OR 区块链 OR IT OR 国际时事")
	rssURLGoogle := fmt.Sprintf("https://news.google.com/rss/search?q=%s&hl=zh-CN&gl=CN", rssQueryGoogle)

	// 【修复】: 定义所有可用的新闻源，并明确指定其 Type
	newsSources := []NewsSource{
		{
			Name: "YouTube 中文热搜 (AI/IT/科技)",
			API:  fmt.Sprintf("https://api.rss2json.com/v1/api.json?rss_url=%s", url.QueryEscape("https://www.youtube.com/feeds/videos.xml?channel_id=UCaT8sendP_s_U4L_D3q_V-g")), // 使用一个科技频道的Feed作为示例
			Type: "RSS2JSON",
		},
		{
			Name: "Google News 中文资讯",
			API:  fmt.Sprintf("https://api.rss2json.com/v1/api.json?rss_url=%s", url.QueryEscape(rssURLGoogle)),
			Type: "RSS2JSON",
		},
		{
			Name: "币圈头条 (Cointelegraph)",
			// 【修复】: 替换了失效的 coinmarketcap.cn API，改用更稳定的 Cointelegraph 中文 RSS Feed
			API:  fmt.Sprintf("https://api.rss2json.com/v1/api.json?rss_url=%s", url.QueryEscape("https://cointelegraph.com/rss/category/china")),
			Type: "RSS2JSON",
		},
	}

	// 解决 rand.Shuffle 兼容性问题：手动实现 Fisher-Yates 洗牌算法
	sourceCount := len(newsSources)

	// 执行洗牌 (使用前面初始化的 r)
	for i := sourceCount - 1; i > 0; i-- {
		// 在 [0, i] 范围内随机选择一个索引
		j := r.Intn(i + 1)
		// 交换元素
		newsSources[i], newsSources[j] = newsSources[j], newsSources[i]
	}

	// 逐个尝试所有来源，直到成功
	for i, source := range newsSources {
		logger.Infof("新闻资讯：开始尝试来源 (随机顺序 [%d/%d]): %s", i+1, len(newsSources), source.Name)

		// 调用核心抓取逻辑
		newsMsg, err := fetchNewsFromGlobalAPI(source, 5) // 直接传递 source 结构体

		if err == nil && newsMsg != "" {
			// 成功获取到内容
			logger.Infof("新闻资讯：来源 [%s] 成功获取内容。", source.Name)
			return newsMsg, nil
		}

		// 失败，记录警告，继续尝试下一个
		logger.Warningf("新闻资讯来源 [%s] 尝试失败: %v", source.Name, err)
	}

	// 所有来源都失败，返回一个友好的错误信息
	return "", errors.New("所有新闻来源均获取失败，请检查网络或 API 状态")
}

// 【新增的辅助函数】: 发送贴纸到指定的聊天 ID，并返回消息对象（用于获取 ID）
func (t *Tgbot) SendStickerToTgbot(chatId int64, fileId string) (*telego.Message, error) {
	// 必须使用 SendStickerParams 结构体，并传入 context
	params := telego.SendStickerParams{
		ChatID: tu.ID(chatId),
		// 对于现有 File ID 字符串，必须封装在 telego.InputFile 结构中。
		Sticker: telego.InputFile{FileID: fileId}, 
	}
	
	// 使用全局变量 bot 调用 SendSticker，并传入 context.Background() 和参数指针
	msg, err := bot.SendSticker(context.Background(), &params)
	
	if err != nil {
		logger.Errorf("发送贴纸失败到聊天 ID %d: %v", chatId, err)
		return nil, err
	}
	
	// 成功返回 *telego.Message 对象
	return msg, nil
}
