#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

#Add some basic function here
function LOGD() {
    echo -e "${yellow}[DEG] $* ${plain}"
}

function LOGE() {
    echo -e "${red}[ERR] $* ${plain}"
}

function LOGI() {
    echo -e "${green}[INF] $* ${plain}"
}

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误: ${plain} 请使用 root 权限运行此脚本\n" && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo -e "${red}检查服务器操作系统失败，请联系作者!${plain}" >&2
    exit 1
fi

echo -e "——————————————————————"
echo -e "当前服务器的操作系统为:${red} $release${plain}"
echo ""
xui_version=$(/usr/local/x-ui/x-ui -v)
last_version=$(curl -Ls "https://api.github.com/repos/xeefei/x-panel/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo -e "${green}当前代理面板的版本为: ${red}〔X-Panel面板〕v${xui_version}${plain}"
echo ""
echo -e "${yellow}〔X-Panel面板〕最新版为---------->>> ${last_version}${plain}"

os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} 请使用 CentOS 8 或更高版本 ${plain}\n" && exit 1
    fi
if [[ "${release}" == "anolis" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} 请使用 Anolis 8 或更高版本 ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "ubuntu" ]]; then
    if [[ ${os_version} -lt 20 ]]; then
        echo -e "${red} 请使用 Ubuntu 20 或更高版本!${plain}\n" && exit 1
    fi

elif [[ "${release}" == "fedora" ]]; then
    if [[ ${os_version} -lt 36 ]]; then
        echo -e "${red} 请使用 Fedora 36 或更高版本!${plain}\n" && exit 1
    fi

elif [[ "${release}" == "debian" ]]; then
    if [[ ${os_version} -lt 11 ]]; then
        echo -e "${red} 请使用 Debian 11 或更高版本 ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "almalinux" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} 请使用 AlmaLinux 9 或更高版本 ${plain}\n" && exit 1
    fi

elif [[ "${release}" == "rocky" ]]; then
    if [[ ${os_version} -lt 9 ]]; then
        echo -e "${red} 请使用 RockyLinux 9 或更高版本 ${plain}\n" && exit 1
    fi
elif [[ "${release}" == "arch" ]]; then
    echo "您的操作系统是 ArchLinux"
elif [[ "${release}" == "manjaro" ]]; then
    echo "您的操作系统是 Manjaro"
elif [[ "${release}" == "armbian" ]]; then
    echo "您的操作系统是 Armbian"
elif [[ "${release}" == "alpine" ]]; then
    echo "您的操作系统是 Alpine Linux"
elif [[ "${release}" == "opensuse-tumbleweed" ]]; then
    echo "您的操作系统是 OpenSUSE Tumbleweed"
elif [[ "${release}" == "oracle" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} 请使用 Oracle Linux 8 或更高版本 ${plain}\n" && exit 1
    fi
else
    echo -e "${red}此脚本不支持您的操作系统。${plain}\n"
    echo "请确保您使用的是以下受支持的操作系统之一："
    echo "- Ubuntu 20.04+"
    echo "- Debian 11+"
    echo "- CentOS 8+"
    echo "- Anolis 8+"
    echo "- Fedora 36+"
    echo "- Arch Linux"
    echo "- Parch Linux"
    echo "- Manjaro"
    echo "- Armbian"
    echo "- Alpine Linux"
    echo "- AlmaLinux 9+"
    echo "- Rocky Linux 9+"
    echo "- Oracle Linux 8+"
    echo "- OpenSUSE Tumbleweed"
    exit 1

fi

# Declare Variables
log_folder="${XUI_LOG_FOLDER:=/var/log}"
iplimit_log_path="${log_folder}/3xipl.log"
iplimit_banned_log_path="${log_folder}/3xipl-banned.log"

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Default $2]: " temp
        if [[ "${temp}" == "" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ "${temp}" == "y" || "${temp}" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "重启面板，注意：重启面板也会重启 Xray" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按 Enter 键返回主菜单：${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls ${GH_PROXY}https://raw.githubusercontent.com/xeefei/x-panel/main/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    confirm "$(echo -e "${green}该功能将强制安装最新版本，并且数据不会丢失。${red}你想继续吗？${plain}---->>请输入")" "y"
    if [[ $? != 0 ]]; then
        LOGE "已取消"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    bash <(curl -Ls ${GH_PROXY}https://raw.githubusercontent.com/xeefei/x-panel/main/install.sh)
    if [[ $? == 0 ]]; then
        LOGI "更新完成，面板已自动重启"
        exit 0
    fi
}

update_menu() {
    echo -e "${yellow}更新菜单项${plain}"
    confirm "此功能会将所有菜单项更新为最新显示状态" "y"
    if [[ $? != 0 ]]; then
        LOGE "Cancelled"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 0
    fi
    
    wget --no-check-certificate -O /usr/bin/x-ui ${GH_PROXY}https://raw.githubusercontent.com/xeefei/x-panel/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    
     if [[ $? == 0 ]]; then
        echo -e "${green}更新成功，面板已自动重启${plain}"
        exit 0
    else
        echo -e "${red}更新菜单项失败${plain}"
        return 1
    fi
}

custom_version() {
    echo "输入面板版本 (例: 2.3.8):"
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "面板版本不能为空。"
        exit 1
    fi

    download_link="${GH_PROXY}https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh"

    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls $download_link) v$panel_version"

    echo "下载并安装面板版本 $panel_version..."
    eval $install_command
}

# Function to handle the deletion of the script file
delete_script() {
    rm "$0"  # Remove the script file itself
    exit 1
}

uninstall() {
    confirm "您确定要卸载面板吗? Xray 也将被卸载!" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop x-ui
    systemctl disable x-ui
    rm /etc/systemd/system/x-ui.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/x-ui/ -rf
    rm /usr/local/x-ui/ -rf

    echo ""
    echo -e "卸载成功\n"
    echo "如果您需要再次安装此面板，可以使用以下命令:"
    echo -e "${green}bash <(curl -Ls ${GH_PROXY}https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh)${plain}"
    echo ""
    # Trap the SIGTERM signal
    trap delete_script SIGTERM
    delete_script
}

reset_user() {
    confirm "您确定重置面板的用户名和密码吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    read -rp "请设置用户名 [默认为随机用户名]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "请设置密码 [默认为随机密码]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/x-ui/x-ui setting -remove_secret >/dev/null 2>&1
    echo -e "面板登录用户名已重置为：${green} ${config_account} ${plain}"
    echo -e "面板登录密码已重置为：${green} ${config_password} ${plain}"
    echo -e "${yellow} 面板 Secret Token 已禁用 ${plain}"
    echo -e "${green} 请使用新的登录用户名和密码访问 X-Panel 面板。也请记住它们！${plain}"
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}修改访问路径${plain}"
    
    # Prompt user to set a new web base path
    read -rp "请设置新的访问路径（若回车默认或输入y则为随机路径）: " config_webBasePath
    
    if [[ $config_webBasePath == "y" ]]; then
        config_webBasePath=$(gen_random_string 18)
    fi
    
    # Apply the new web base path setting
    /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}" >/dev/null 2>&1
    systemctl restart x-ui
    
    # Display confirmation message
    echo -e "面板访问路径已重置为: ${green}${config_webBasePath}${plain}"
    echo -e "${green}请使用新的路径登录访问面板${plain}"
}

reset_config() {
    confirm "您确定要重置所有面板设置，帐户数据不会丢失，用户名和密码不会更改" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    /usr/local/x-ui/x-ui setting -reset
    echo -e "所有面板设置已重置为默认，请立即重新启动面板，并使用默认的${green}13688${plain}端口访问网页面板"
    confirm_restart
}

check_config() {
    info=$(/usr/local/x-ui/x-ui setting -show true)
    if [[ $? != 0 ]]; then
        LOGE "获取当前设置错误，请检查日志"
        show_menu
    fi
    echo -e "${info}${plain}"
    echo ""
    
    # 获取 IPv4 和 IPv6 地址
    v4=$(curl -s4m8 http://ip.sb -k)
    v6=$(curl -s6m8 http://ip.sb -k)
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath（访问路径）: .+' | awk '{print $2}') 
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port（端口号）: .+' | awk '{print $2}') 
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        echo -e "${green}面板已安装证书采用SSL保护${plain}"
        echo ""
        local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
        domain=$(basename "$(dirname "$existing_cert")")
        echo -e "${green}登录访问面板URL: https://${domain}:${existing_port}${green}${existing_webBasePath}${plain}"
    fi
    echo ""
    if [[ -z "$existing_cert" && -z "$existing_key" ]]; then
        echo -e "${red}警告：未找到证书和密钥，面板不安全！${plain}"
        echo ""
        echo -e "${green}------->>>>请按照下述方法设置〔ssh转发〕<<<<-------${plain}"
        echo ""

        # 检查 IP 并输出相应的 SSH 和浏览器访问信息
        if [[ -z $v4 ]]; then
            echo -e "${green}1、本地电脑客户端转发命令：${plain} ${blue}ssh  -L [::]:15208:127.0.0.1:${existing_port}${blue} root@[$v6]${plain}"
            echo ""
            echo -e "${green}2、请通过快捷键【Win + R】调出运行窗口，在里面输入【cmd】打开本地终端服务${plain}"
            echo ""
            echo -e "${green}3、请在终端中成功输入服务器的〔root密码〕，注意区分大小写，用以上命令进行转发${plain}"
            echo ""
            echo -e "${green}4、请在浏览器地址栏复制${plain} ${blue}[::1]:15208${existing_webBasePath}${plain} ${green}进入〔X-Panel面板〕登录界面"
            echo ""
            echo -e "${red}注意：若不使用〔ssh转发〕请为X-Panel面板配置安装证书再行登录管理后台${plain}"
        elif [[ -n $v4 && -n $v6 ]]; then
            echo -e "${green}1、本地电脑客户端转发命令：${plain} ${blue}ssh -L 15208:127.0.0.1:${existing_port}${blue} root@$v4${plain} ${yellow}或者 ${blue}ssh  -L [::]:15208:127.0.0.1:${existing_port}${blue} root@[$v6]${plain}"
            echo ""
            echo -e "${green}2、请通过快捷键【Win + R】调出运行窗口，在里面输入【cmd】打开本地终端服务${plain}"
            echo ""
            echo -e "${green}3、请在终端中成功输入服务器的〔root密码〕，注意区分大小写，用以上命令进行转发${plain}"
            echo ""
            echo -e "${green}4、请在浏览器地址栏复制${plain} ${blue}127.0.0.1:15208${existing_webBasePath}${plain} ${yellow}或者${plain} ${blue}[::1]:15208${existing_webBasePath}${plain} ${green}进入〔X-Panel面板〕登录界面"
            echo ""
            echo -e "${red}注意：若不使用〔ssh转发〕请为X-Panel面板配置安装证书再行登录管理后台${plain}"
        else
            echo -e "${green}1、本地电脑客户端转发命令：${plain} ${blue}ssh -L 15208:127.0.0.1:${existing_port}${blue} root@$v4${plain}"
            echo ""
            echo -e "${green}2、请通过快捷键【Win + R】调出运行窗口，在里面输入【cmd】打开本地终端服务${plain}"
            echo ""
            echo -e "${green}3、请在终端中成功输入服务器的〔root密码〕，注意区分大小写，用以上命令进行转发${plain}"
            echo ""
            echo -e "${green}4、请在浏览器地址栏复制${plain} ${blue}127.0.0.1:15208${existing_webBasePath}${plain} ${green}进入〔X-Panel面板〕登录界面"
            echo ""
            echo -e "${red}注意：若不使用〔ssh转发〕请为X-Panel面板配置安装证书再行登录管理后台${plain}"
            echo ""
        fi
    fi
}

set_port() {
    echo && echo -n -e "输入端口号 [1-65535]: " && read port
    if [[ -z "${port}" ]]; then
        LOGD "Cancelled"
        before_show_menu
    else
        /usr/local/x-ui/x-ui setting -port ${port}
        echo -e "端口已设置，请立即重启面板，并使用新端口 ${green}${port}${plain} 以访问面板"
        confirm_restart
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        LOGI "面板正在运行，无需再次启动，如需重新启动，请选择重新启动"
    else
        systemctl start x-ui
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            LOGI "X-Panel 已成功启动"
        else
            LOGE "面板启动失败，可能是启动时间超过两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    check_status
    if [[ $? == 1 ]]; then
        echo ""
        LOGI "面板已关闭，无需再次关闭！"
    else
        systemctl stop x-ui
        sleep 2
        check_status
        if [[ $? == 1 ]]; then
            LOGI "X-Panel 和 Xray 已成功关闭"
        else
            LOGE "面板关闭失败，可能是停止时间超过两秒，请稍后查看日志信息"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart x-ui
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        LOGI "X-Panel 和 Xray 已成功重启"
    else
        LOGE "面板重启失败，可能是启动时间超过两秒，请稍后查看日志信息"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status x-ui -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 已成功设置开机启动"
    else
        LOGE "x-ui 设置开机启动失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable x-ui
    if [[ $? == 0 ]]; then
        LOGI "x-ui 已成功取消开机启动"
    else
        LOGE "x-ui 取消开机启动失败"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u x-ui.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

bbr_menu() {
    echo -e "${green}\t1.${plain} 启用 BBR"
    echo -e "${green}\t2.${plain} 禁用 BBR"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请输入选项: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        enable_bbr
        ;;
    2)
        disable_bbr
        ;;
    *) echo "无效选项" ;;
    esac
}

disable_bbr() {
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${yellow}BBR 当前未启用${plain}"
        exit 0
    fi

    # Replace BBR with CUBIC configurations
    sed -i 's/net.core.default_qdisc=fq/net.core.default_qdisc=pfifo_fast/' /etc/sysctl.conf
    sed -i 's/net.ipv4.tcp_congestion_control=bbr/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf

    # Apply changes
    sysctl -p

    # Verify that BBR is replaced with CUBIC
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "cubic" ]]; then
        echo -e "${green}BBR 已成功替换为 CUBIC${plain}"
    else
        echo -e "${red}用 CUBIC 替换 BBR 失败，请检查您的系统配置。${plain}"
    fi
}

enable_bbr() {
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}BBR 已经启用!${plain}"
        exit 0
    fi

    # Check the OS and install necessary packages
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky | oracle | anolis)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro)
        pacman -Sy --noconfirm ca-certificates
        ;;
    *)
        echo -e "${red}不支持的操作系统。请检查脚本并手动安装必要的软件包${plain}\n"
        exit 1
        ;;
    esac

    # Enable BBR
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    # Apply changes
    sysctl -p

    # Verify that BBR is enabled
    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR 已成功启用${plain}"
    else
        echo -e "${red}启用 BBR 失败，请检查您的系统配置${plain}"
    fi
}

update_shell() {
    wget -O /usr/bin/x-ui -N --no-check-certificate ${GH_PROXY}https://github.com/xeefei/x-panel/raw/main/x-ui.sh
    if [[ $? != 0 ]]; then
        echo ""
        LOGE "下载脚本失败，请检查机器是否可以连接至 GitHub"
        before_show_menu
    else
        chmod +x /usr/bin/x-ui
        LOGI "升级脚本成功，请重新运行脚本" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        return 2
    fi
    temp=$(systemctl status x-ui | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ "${temp}" == "running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled x-ui)
    if [[ "${temp}" == "enabled" ]]; then
        return 0
    else
        return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        LOGE "面板已安装，请勿重新安装"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        LOGE "请先安装面板"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
    0)
        echo -e "面板状态: ${green}运行中${plain}"
        show_enable_status
        ;;
    1)
        echo -e "面板状态: ${yellow}未运行${plain}"
        show_enable_status
        ;;
    2)
        echo -e "面板状态: ${red}未安装${plain}"
        ;;
    esac
    show_xray_status
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "开机启动: ${green}是${plain}"
    else
        echo -e "开机启动: ${red}否${plain}"
    fi
}

check_xray_status() {
    count=$(ps -ef | grep "xray-linux" | grep -v "grep" | wc -l)
    if [[ count -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

show_xray_status() {
    check_xray_status
    if [[ $? == 0 ]]; then
        echo -e "Xray状态: ${green}运行中${plain}"
    else
        echo -e "Xray状态: ${red}未运行${plain}"
    fi
}

firewall_menu() {
    echo -e "${green}\t1.${plain} 安装防火墙并开放端口"
    echo -e "${green}\t2.${plain} 允许列表"
    echo -e "${green}\t3.${plain} 从列表中删除端口"
    echo -e "${green}\t4.${plain} 禁用防火墙"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请输入选项: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        open_ports
        ;;
    2)
        sudo ufw status
        ;;
    3)
        delete_ports
        ;;
    4)
        sudo ufw disable
        ;;
    *) echo "无效选项" ;;
    esac
}

open_ports() {
    if ! command -v ufw &>/dev/null; then
        echo "ufw 防火墙未安装，正在安装..."
        apt-get update
        apt-get install -y ufw
    else
        echo "ufw 防火墙已安装"
    fi

    # Check if the firewall is inactive
    if ufw status | grep -q "Status: active"; then
        echo "防火墙已经激活"
    else
        # Open the necessary ports
        ufw allow ssh
        ufw allow http
        ufw allow https
        ufw allow 13688/tcp

        # Enable the firewall
        ufw --force enable
    fi

    # Prompt the user to enter a list of ports
    read -p "输入您要打开的端口（例如 80,443,13688 或端口范围 400-500): " ports

    # Check if the input is valid
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "错误：输入无效。请输入以英文逗号分隔的端口列表或端口范围（例如 80,443,13688 或 400-500)" >&2
        exit 1
    fi

    # Open the specified ports using ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Split the range into start and end ports
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Loop through the range and open each port
            for ((i = start_port; i <= end_port; i++)); do
                ufw allow $i
            done
        else
            ufw allow "$port"
        fi
    done

    # Confirm that the ports are open
    ufw status | grep $ports
}

delete_ports() {
    # Prompt the user to enter the ports they want to delete
    read -p "输入要删除的端口（例如 80,443,13688 或范围 400-500): " ports

    # Check if the input is valid
    if ! [[ $ports =~ ^([0-9]+|[0-9]+-[0-9]+)(,([0-9]+|[0-9]+-[0-9]+))*$ ]]; then
        echo "错误：输入无效。请输入以英文逗号分隔的端口列表或端口范围（例如 80,443,13688 或 400-500)" >&2
        exit 1
    fi

    # Delete the specified ports using ufw
    IFS=',' read -ra PORT_LIST <<<"$ports"
    for port in "${PORT_LIST[@]}"; do
        if [[ $port == *-* ]]; then
            # Split the range into start and end ports
            start_port=$(echo $port | cut -d'-' -f1)
            end_port=$(echo $port | cut -d'-' -f2)
            # Loop through the range and delete each port
            for ((i = start_port; i <= end_port; i++)); do
                ufw delete allow $i
            done
        else
            ufw delete allow "$port"
        fi
    done

    # Confirm that the ports are deleted
    echo "删除指定端口:"
    ufw status | grep $ports
}

update_geo() {
    local defaultBinFolder="/usr/local/x-ui/bin"
    read -p "请输入 x-ui bin 文件夹路径，默认留空。（默认值：'${defaultBinFolder}')" binFolder
    binFolder=${binFolder:-${defaultBinFolder}}
    if [[ ! -d ${binFolder} ]]; then
        LOGE "文件夹 ${binFolder} 不存在！"
        LOGI "制作 bin 文件夹：${binFolder}..."
        mkdir -p ${binFolder}
    fi

    systemctl stop x-ui
    cd ${binFolder}
    rm -f geoip.dat geosite.dat geoip_IR.dat geosite_IR.dat geoip_VN.dat geosite_VN.dat
    wget -N ${GH_PROXY}https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
    wget -N ${GH_PROXY}https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
    wget -O geoip_IR.dat -N ${GH_PROXY}https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_IR.dat -N ${GH_PROXY}https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
    wget -O geoip_VN.dat ${GH_PROXY}https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_VN.dat ${GH_PROXY}https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geosite.dat
    systemctl start x-ui
    echo -e "${green}Geosite.dat + Geoip.dat + geoip_IR.dat + geosite_IR.dat 在 bin 文件夹: '${binfolder}' 中已经更新成功 !${plain}"
    before_show_menu
}

install_acme() { 
    # 检查是否已安装 acme.sh
    if command -v ~/.acme.sh/acme.sh &>/dev/null; then 
        LOGI "acme.sh 已经安装。" 
        return 0 
    fi 
 
    LOGI "正在安装 acme.sh..." 
    cd ~ || return 1 # 确保可以切换到主目录
 
    curl -s https://get.acme.sh | sh 
    if [ $? -ne 0 ]; then 
        LOGE "安装 acme.sh 失败。" 
        return 1 
    else 
        LOGI "安装 acme.sh 成功。" 
    fi 
 
    return 0 
}

# 【中文注释】：“备用方式申请证书”函数
ssl_cert_issue_standalone_embedded() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath（访问路径）: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port（端口号）: .+' | awk '{print $2}')
    echo ""
    echo -e "${yellow}=== 备用方式申请 SSL 证书 (Standalone 模式) ===${plain}"
    echo ""
    echo -e "${yellow}说明：此模式使用 80 端口申请证书，成功率高，但需要占用 80 端口。${plain}"
    echo ""

    # --- 1. 用户输入信息 ---
    read -rp "请输入域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        LOGE "域名不能为空"
        echo ""
        return 1
    fi

    read -rp "请输入电子邮件地址 (用于注册账户): " EMAIL
    if [ -z "$EMAIL" ]; then
        LOGE "邮箱不能为空"
        return 1
    fi

    echo -e "请选择证书颁发机构（CA）："
    echo ""
    echo -e "${green}1)${plain} Let's Encrypt"
    echo ""
    echo -e "${green}2)${plain} Buypass"
    echo ""
    echo -e "${green}3)${plain} ZeroSSL"
    echo ""
    read -rp "输入选项（1-3）： " CA_OPTION
    case $CA_OPTION in
        1) CA_SERVER="letsencrypt" ;;
        2) CA_SERVER="buypass" ;;
        3) CA_SERVER="zerossl" ;;
        *) echo "❌ 无效选项"; return 1 ;;
    esac

    # --- 2. 防火墙与端口处理  ---
    echo ""
    echo -e "${yellow}注意：Standalone 模式必须使用 80 端口。${plain}"
    echo ""
    echo -e "脚本可以尝试临时放行端口或关闭防火墙，申请结束后您可以手动恢复。"
    echo ""
    echo -e "${green}1)${plain} 尝试关闭防火墙 (成功率最高)"
    echo ""
    echo -e "${green}2)${plain} 尝试仅放行 80 端口"
    echo ""
    echo -e "${green}3)${plain} 跳过防火墙设置 (如果您已确认 80 端口开放)"
    echo ""
    read -rp "输入选项（1-3）：" FIREWALL_OPTION

    # 检测系统类型
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
    else
        echo "❌ 无法识别操作系统，跳过依赖安装优化。"
    fi

    # 执行防火墙操作
    if [ "$FIREWALL_OPTION" -eq 1 ]; then
        LOGI "正在尝试关闭防火墙..."
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw disable
        elif command -v systemctl >/dev/null 2>&1; then
            sudo systemctl stop firewalld 2>/dev/null
            sudo systemctl stop iptables 2>/dev/null
        fi
    elif [ "$FIREWALL_OPTION" -eq 2 ]; then
        LOGI "正在尝试放行 80 端口..."
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw allow 80
        elif command -v firewall-cmd >/dev/null 2>&1; then
            sudo firewall-cmd --permanent --add-port=80/tcp
            sudo firewall-cmd --reload
        fi
    fi

    # --- 3. 安装依赖 (socat 是 standalone 模式必须的) ---
    LOGI "正在检查并安装必要依赖 (socat)..."
    case $OS in
        ubuntu|debian)
            sudo apt update -y
            sudo apt install -y curl socat cron
            ;;
        centos|almalinux|rocky)
            sudo yum update -y
            sudo yum install -y curl socat cronie
            sudo systemctl start crond
            sudo systemctl enable crond
            ;;
        *)
            # 其他系统尝试通用安装
            if ! command -v socat >/dev/null 2>&1; then
                echo "❌ 无法识别系统包管理器，请手动安装 socat。"
                return 1
            fi
            ;;
    esac

    # --- 4. 安装/检查 acme.sh ---
    if ! command -v ~/.acme.sh/acme.sh >/dev/null 2>&1; then
        LOGI "未检测到 acme.sh，正在安装..."
        curl https://get.acme.sh | sh
        if [ $? -ne 0 ]; then
            LOGE "acme.sh 安装失败！"
            return 1
        fi
        export PATH="$HOME/.acme.sh:$PATH"
        ~/.acme.sh/acme.sh --upgrade
    else
        LOGI "acme.sh 已安装。"
    fi

    # --- 5. 注册账户 ---
    LOGI "正在注册 ACME 账户..."
    ~/.acme.sh/acme.sh --register-account -m $EMAIL --server $CA_SERVER

    # --- 6. 申请证书 (Standalone 模式) ---
    LOGI "正在使用 Standalone 模式申请证书 (占用 80 端口)..."
    # 如果 80 端口被 nginx 或 x-ui 占用，先尝试停止它们
    systemctl stop nginx >/dev/null 2>&1
    systemctl stop x-ui >/dev/null 2>&1
    
    if ! ~/.acme.sh/acme.sh --issue --standalone -d $DOMAIN --server $CA_SERVER --force; then
        LOGE "❌ 证书申请失败！"
        LOGE "请检查：1、域名解析是否正确指向本机 IP。2、80 端口是否开放且未被占用。"
        # 失败尝试重启 x-ui
        systemctl start x-ui >/dev/null 2>&1
        return 1
    fi

# --- 7. 安装证书到标准路径 ---
# 直接创建 x-ui 标准目录结构，
    local certPath="/root/cert/${DOMAIN}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    fi
    
    LOGI "申请成功！正在安装证书到: $certPath"
    
    # x-ui 是系统服务，用 systemctl restart x-ui 更稳妥
    local reloadCmd="systemctl restart x-ui" 
    
    ~/.acme.sh/acme.sh --installcert -d $DOMAIN \
        --key-file       "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        --reloadcmd      "${reloadCmd}"
        
    if [ $? -eq 0 ]; then
        LOGI "✅ 证书安装命令执行成功！"
        # 启用 acme.sh 自动升级
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        
        # --- 8. 自动应用到面板设置 (包含文件检查) ---
        local webCertFile="${certPath}/fullchain.pem"
        local webKeyFile="${certPath}/privkey.pem"
        
        # === 文件检查判断 ===
        if [[ -f "${webCertFile}" && -f "${webKeyFile}" && -s "${webCertFile}" && -s "${webKeyFile}" ]]; then
            
            LOGI "检测到证书文件存在且有效，正在应用到 X-Panel 面板..."
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            
            echo -e "${green}恭喜！备用方式证书申请并配置成功！${plain}"
            echo ""
            echo "  - 域名：$DOMAIN"
            echo ""
            echo "  - 证书路径：$webCertFile"
            echo ""
            echo "  - 私钥路径：$webKeyFile"
            echo ""
            echo -e "${green}登录访问面板URL: https://${domain}:${existing_port}${green}${existing_webBasePath}${plain}"
            echo ""
            echo -e "${green}PS：若您要登录访问面板，请复制上面的地址到浏览器打开即可${plain}"
            echo ""
            
            # 重启面板以生效
            if command -v restart >/dev/null 2>&1; then
                restart
            else
                systemctl restart x-ui
            fi
        else
            LOGE "❌ 严重错误：证书安装显示成功，但未找到证书文件或文件为空！"
            LOGE "请检查目录权限或磁盘空间：$certPath"
            # 恢复 x-ui 运行，避免断联
            systemctl start x-ui >/dev/null 2>&1
            return 1
        fi
    else
        LOGE "证书安装步骤失败，请检查日志。"
        systemctl start x-ui >/dev/null 2>&1
    fi
}

ssl_cert_issue_main() { 
    echo -e "${green}\t1.${plain} 获取 SSL 证书" 
    echo -e "${green}\t2.${plain} 撤销证书" 
    echo -e "${green}\t3.${plain} 强制更新证书" 
    echo -e "${green}\t4.${plain} 自定义证书路径" 
    echo -e "${green}\t5.${plain} 备用方式申请证书" 
    echo -e "${green}\t6.${plain} 显示现有域名" 
    echo -e "${green}\t7.${plain} 为面板设置证书路径" 
    echo -e "${green}\t0.${plain} 返回主菜单"
    echo "" 
 
    read -rp "请选择一个选项：" choice 
    case "$choice" in 
    0) 
        show_menu 
        ;; 
    1) 
        ssl_cert_issue 
        ssl_cert_issue_main 
        ;; 
    2) 
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;) 
        if [ -z "$domains" ]; then 
            echo "未找到可撤销的证书。" 
        else 
            echo "现有域名：" 
            echo "$domains" 
            read -rp "请从列表中输入要撤销证书的域名：" domain 
            if echo "$domains" | grep -qw "$domain"; then 
                ~/.acme.sh/acme.sh --revoke -d ${domain} 
                LOGI "已撤销域名的证书：$domain" 
            else 
                echo "输入的域名无效。" 
            fi 
        fi 
        ssl_cert_issue_main 
        ;; 
    3) 
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;) 
        if [ -z "$domains" ]; then 
            echo "未找到可更新的证书。" 
        else 
            echo "现有域名：" 
            echo "$domains" 
            read -rp "请从列表中输入要强制更新 SSL 证书的域名：" domain 
            if echo "$domains" | grep -qw "$domain"; then 
                ~/.acme.sh/acme.sh --renew -d ${domain} --force 
                LOGI "已强制更新域名的证书：$domain" 
            else 
                echo "输入的域名无效。" 
            fi 
        fi 
        ssl_cert_issue_main 
        ;; 
    4) 
        # 【功能：自定义证书路径】
        local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath（访问路径）: .+' | awk '{print $2}')
        local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port（端口号）: .+' | awk '{print $2}')
        echo ""
        echo -e "${yellow}您选择了“手动上传证书”去自定义路径${plain}"
        echo ""
        echo -e "${red}请您务必先以〔“root”用户〕上传您的证书文件${plain}"
        echo ""
        read -rp "请输入您的域名: " domain
        echo ""
        read -rp "请输入公钥文件(Fullchain/Cert)的绝对路径: " user_cert
        echo ""
        read -rp "请输入私钥文件(Key)的绝对路径: " user_key

        # 源文件检查，增加 -s 判断，防止用户上传了空文件
        if [[ -f "$user_cert" && -f "$user_key" && -s "$user_cert" && -s "$user_key" ]]; then
            
            # 创建标准存放目录
            local certPath="/root/cert/${domain}"
            if [ ! -d "$certPath" ]; then
                mkdir -p "$certPath"
            fi
            
            # 复制文件到 X-Panel 标准目录，统一命名
            # 使用 \cp -f 强制覆盖，不提示
            \cp -f "$user_cert" "${certPath}/fullchain.pem"
            \cp -f "$user_key" "${certPath}/privkey.pem"
            
            local webCertFile="${certPath}/fullchain.pem"
            local webKeyFile="${certPath}/privkey.pem"

            # 检查复制后的目标文件是否存在且不为空
            if [[ -f "${webCertFile}" && -f "${webKeyFile}" && -s "${webCertFile}" && -s "${webKeyFile}" ]]; then
                
                # 应用到面板设置
                /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
                
                echo -e "${green}已成功导入证书并设置应用到面板路径！${plain}"
                echo ""
                echo "  - 域名：$domain"
                echo ""
                echo "  - 证书文件：$webCertFile"
                echo ""
                echo "  - 私钥文件：$webKeyFile"
                echo ""
                echo -e "${green}登录访问面板URL: https://${domain}:${existing_port}${green}${existing_webBasePath}${plain}"
                echo ""
                echo -e "${green}PS：若您要登录访问面板，请复制上面的地址到浏览器打开即可${plain}"
                echo ""
                
                # 只有文件确认无误，才执行重启
                restart
            else
                # 复制失败的处理
                LOGE "❌ 严重错误：文件复制失败或目标文件为空！"
                echo "可能是磁盘空间不足或权限问题，面板设置未更改。"
            fi
        else
            echo -e "${red}错误：找不到文件或文件为空 (0KB)，请检查后重试！${plain}"
            echo ""
            echo "公钥路径: $user_cert"
            echo ""
            echo "私钥路径: $user_key"
        fi
        
        # 返回主菜单
        ssl_cert_issue_main
        ;;
    5)
        # 【功能：备用方式申请证书】
        ssl_cert_issue_standalone_embedded
        ssl_cert_issue_main
        ;;
    6) 
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;) 
        if [ -z "$domains" ]; then 
            echo "未找到证书。" 
        else 
            echo "现有域名及其路径：" 
            for domain in $domains; do 
                local cert_path="/root/cert/${domain}/fullchain.pem" 
                local key_path="/root/cert/${domain}/privkey.pem" 
                if [[ -f "${cert_path}" && -f "${key_path}" ]]; then 
                    echo -e "域名：${domain}"
                    echo "" 
                    echo -e "\t证书路径：${cert_path}"
                    echo "" 
                    echo -e "\t私钥路径：${key_path}" 
                else 
                    echo -e "域名：${domain} - 证书或私钥文件缺失。" 
                fi 
            done 
        fi 
        ssl_cert_issue_main 
        ;; 
    7) 
        local domains=$(find /root/cert/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;) 
        if [ -z "$domains" ]; then 
            echo "未找到证书。" 
        else 
            echo "可用域名：" 
            echo "$domains" 
            read -rp "请选择要为面板设置证书路径的域名：" domain 
 
            if echo "$domains" | grep -qw "$domain"; then 
                local webCertFile="/root/cert/${domain}/fullchain.pem" 
                local webKeyFile="/root/cert/${domain}/privkey.pem" 
 
                if [[ -f "${webCertFile}" && -f "${webKeyFile}" ]]; then 
                    /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile" 
                    echo "已为域名设置面板证书路径：$domain"
                    echo "" 
                    echo "  - 证书文件：$webCertFile"
                    echo "" 
                    echo "  - 私钥文件：$webKeyFile" 
                    restart 
                else 
                    echo "未找到域名的证书或私钥：$domain" 
                fi 
            else 
                echo "输入的域名无效。" 
            fi 
        fi 
        ssl_cert_issue_main 
        ;; 
 
    *) 
        echo -e "${red}无效选项，请选择有效的数字。${plain}\n" 
        ssl_cert_issue_main 
        ;; 
    esac 
}

ssl_cert_issue() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath（访问路径）: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port（端口号）: .+' | awk '{print $2}')
    # 首先检查 acme.sh
    echo ""
    if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
        echo "未找到 acme.sh，将进行安装"
        install_acme
        if [ $? -ne 0 ]; then
            LOGE "安装 acme 失败，请检查日志"
            exit 1
        fi
    fi

    # 安装 socat 和 dnsutils/bind-utils (用于 dig)
    case "${release}" in
    ubuntu | debian | armbian)
        # 添加了 dnsutils 用于 dig 命令
        apt update && apt install socat dnsutils -y
        ;;
    centos | rhel | almalinux | rocky | ol | anolis)
        # 添加了 bind-utils 用于 dig 命令
        yum -y update && yum -y install socat bind-utils
        ;;
    fedora | amzn | virtuozzo)
        # 添加了 bind-utils 用于 dig 命令
        dnf -y update && dnf -y install socat bind-utils
        ;;
    arch | manjaro | parch)
        # 添加了 dnsutils 用于 dig 命令
        pacman -Sy --noconfirm socat dnsutils
        ;;
    *)
        echo ""
        echo -e "${red}不支持的操作系统。请检查脚本并手动安装必要的软件包。${plain}\n"
        exit 1
        ;;
    esac
    if [ $? -ne 0 ]; then
        LOGE "安装 socat 或 dig 工具 失败，请检查日志"
        echo ""
        exit 1
    else
        LOGI "安装 socat 和 dig 工具 成功..."
        echo ""
    fi

    # 在这里获取域名，我们需要验证它
    local domain=""
    # 强制从终端读取输入，避免被管道跳过
    read -rp "请输入您的域名: " domain </dev/tty
    echo ""
    LOGD "您的域名是: ${domain}, 正在检查..."
    echo ""

    # --- 新增：域名解析验证 ---
    LOGD "正在获取本机公共 IP..."
    echo ""
    public_ip=$(curl -s4m8 http://ip.sb -k)
    
    if [ -z "$public_ip" ]; then
        LOGE "获取本机公共 IP 失败，请检查网络连接！"
        exit 1
    fi
    LOGI "本机公共 IP: ${public_ip}"
    echo ""

    LOGD "正在查询域名 ${domain} 的 DNS ----->>> A 记录..."
    # 确保只获取A记录，并取第一个
    domain_ip=$(dig +short $domain A | head -n 1)

    if [ -z "$domain_ip" ]; then
        echo ""
        LOGE "未能查询到域名 ${domain} 的 “A 记录”。"
        echo ""
        LOGE "请确保您的域名已在 DNS 服务商处添加了〔A 记录〕，并指向本机 IP。"
        echo ""
        LOGE "提示：如果您使用的是 Cloudflare，请确保【小黄云】（代理）已关闭。"
        exit 1
    fi
    LOGI "域名 ${domain} 解析到 IP: ${domain_ip}"
    echo ""

    if [ "$public_ip" != "$domain_ip" ]; then
        echo ""
        LOGE "域名 ${domain} 解析的 IP (${domain_ip}) 与本机 IP (${public_ip}) 不符！"
        echo ""
        LOGE "请检查您的 DNS 中 的〔A 记录〕设置是否正确。"
        echo ""
        LOGE "提示：如果您使用的是 Cloudflare，请确保【小黄云】（代理）已关闭。"
        exit 1
    fi

    LOGI "域名解析验证成功，继续执行证书申请......"
    echo ""

    # 检查是否已存在证书
    local currentCert=$(~/.acme.sh/acme.sh --list | tail -1 | awk '{print $1}')
    if [ "${currentCert}" == "${domain}" ]; then
        local certInfo=$(~/.acme.sh/acme.sh --list)
        LOGE "系统已存在此域名的证书。无法再次签发。当前证书详情:"
        LOGI "$certInfo"
        exit 1
    else
        LOGI "您的域名现在可以签发证书了......"
    fi

    # 为证书创建一个目录
    echo ""
    certPath="/root/cert/${domain}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    else
        rm -rf "$certPath"
        mkdir -p "$certPath"
    fi

    # 获取独立服务器的端口号
    local WebPort=80
    read -rp "请选择要使用的端口 (默认为 80): " WebPort
    if [[ ${WebPort} -gt 65535 || ${WebPort} -lt 1 ]]; then
        LOGE "您输入的 ${WebPort} 无效，将使用默认端口 80。"
        WebPort=80
    fi
    LOGI "将使用端口: ${WebPort} 来签发证书。请确保此端口已开放。"

    # 签发证书
    echo ""
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        LOGE "签发证书失败，请检查日志。"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGE "签发证书成功，正在安装证书..."
    fi

    # --- 自动设置 reloadCmd ---
    echo ""
    reloadCmd="systemctl restart x-ui"
    LOGI "ACME 的 --reloadcmd 已自动设置为: ${yellow}systemctl restart x-ui"
    
    # 安装证书
    echo ""
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem \
        --reloadcmd "${reloadCmd}"

    echo ""
    if [ $? -ne 0 ]; then
        LOGE "安装证书失败，正在退出。"
        rm -rf ~/.acme.sh/${domain}
        exit 1
    else
        LOGI "安装证书成功，正在启用自动续订..."
    fi

    # 启用自动续订
    echo ""
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    if [ $? -ne 0 ]; then
        LOGE "自动续订失败，证书详情："
        ls -lah cert/*
        chmod 755 $certPath/*
        exit 1
    else
        LOGI "自动续订成功，证书详情："
        ls -lah cert/*
        chmod 755 $certPath/*
    fi

    # ---  自动为面板设置证书路径  ---
    echo ""
    local webCertFile="/root/cert/${domain}/fullchain.pem"
    local webKeyFile="/root/cert/${domain}/privkey.pem"

    if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
        /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
        LOGI "已为域名自动设置面板证书路径: $domain"
        echo ""
        LOGI "  - 证书文件: $webCertFile"
        echo ""
        LOGI "  - 私钥文件: $webKeyFile"
        echo ""
        echo -e "${green}登录访问面板URL: https://${domain}:${existing_port}${green}${existing_webBasePath}${plain}"
        echo ""
        echo -e "${green}PS：若您要登录访问面板，请复制上面的地址到浏览器打开即可${plain}"
        echo ""
        restart
    else
        LOGE "错误：未找到域名的证书或私钥文件: $domain。"
    fi
}

ssl_cert_issue_CF() {
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath（访问路径）: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port（端口号）: .+' | awk '{print $2}')
    LOGI "****** 使用说明 ******"
    echo ""
    LOGI "请按照以下步骤完成操作："
    echo ""
    LOGI "1. 准备好在 Cloudflare 注册的电子邮箱。"
    echo ""
    LOGI "2. 准备好 Cloudflare Global API 密钥。"
    echo ""
    LOGI "3. 准备好一个可用的域名。"
    echo ""
    LOGI "4. 证书颁发后，系统将自动为您设置证书路径。"
    echo ""
    LOGI "5. 安装后，脚本还支持自动续订 SSL 证书。"
    echo ""

    confirm "您确认信息并希望继续吗？[y/n]" "y"

    if [ $? -eq 0 ]; then
        # 首先检查 acme.sh
        if ! command -v ~/.acme.sh/acme.sh &>/dev/null; then
            echo "未找到 acme.sh。我们将为您安装。"
            install_acme
            if [ $? -ne 0 ]; then
                LOGE "安装 acme 失败，请检查日志。"
                exit 1
            fi
        fi

        CF_Domain=""

        LOGD "请设置一个域名："
        # 强制从终端读取输入
        read -rp "在此输入您的域名: " CF_Domain </dev/tty
        LOGD "您的域名设置为：${CF_Domain}"

        # 设置 Cloudflare API 详细信息
        CF_GlobalKey=""
        CF_AccountEmail=""
        LOGD "请设置 API 密钥："
        # 强制从终端读取输入
        read -rp "在此输入您的密钥: " CF_GlobalKey </dev/tty
        LOGD "您的 API 密钥是：${CF_GlobalKey}"

        LOGD "请设置注册的电子邮箱："
        # 强制从终端读取输入
        read -rp "在此输入您的电子邮箱: " CF_AccountEmail </dev/tty
        LOGD "您注册的电子邮箱地址是：${CF_AccountEmail}"

        # 将默认 CA 设置为 Let's Encrypt
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
        if [ $? -ne 0 ]; then
            LOGE "设置默认 CA 为 Let's Encrypt 失败，脚本正在退出..."
            exit 1
        fi

        export CF_Key="${CF_GlobalKey}"
        export CF_Email="${CF_AccountEmail}"

        # 使用 Cloudflare DNS 颁发证书
        echo ""
        ~/.acme.sh/acme.sh --issue --dns dns_cf -d ${CF_Domain} -d *.${CF_Domain} --log --force
        if [ $? -ne 0 ]; then
            LOGE "证书颁发失败，脚本正在退出..."
            exit 1
        else
            LOGI "证书颁发成功，正在安装..."
        fi
        
        # 为证书创建一个目录
        echo ""
        certPath="/root/cert/${CF_Domain}"
        if [ -d "$certPath" ]; then
            rm -rf ${certPath}
        fi

        mkdir -p ${certPath}
        if [ $? -ne 0 ]; then
            LOGE "创建目录失败: ${certPath}"
            exit 1
        fi

        # --- 自动设置 reloadCmd ---
        echo ""
        reloadCmd="systemctl restart x-ui"
        LOGI "ACME 的 --reloadcmd 已自动设置为: ${yellow}systemctl restart x-ui"
        echo ""

        # 执行“安装证书”流程
        echo ""
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem \
            --reloadcmd "${reloadCmd}"
        
        echo ""
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败，脚本正在退出..."
            exit 1
        else
            LOGI "证书安装成功，正在开启自动更新..."
        fi

        # 启用自动续订
        echo ""
        ~/.acme.sh/acme.sh --upgrade --auto-upgrade
        if [ $? -ne 0 ]; then
            LOGE "自动续订设置失败，脚本正在退出..."
            exit 1
        else
            LOGI "证书已安装并开启自动续订。具体信息如下："
            ls -lah ${certPath}/*
            chmod 755 ${certPath}/*
        fi

        # --- 自动为面板设置证书路径 ---
        echo ""
        local webCertFile="${certPath}/fullchain.pem"
        local webKeyFile="${certPath}/privkey.pem"

        if [[ -f "$webCertFile" && -f "$webKeyFile" ]]; then
            /usr/local/x-ui/x-ui cert -webCert "$webCertFile" -webCertKey "$webKeyFile"
            echo ""
            LOGI "已为域名自动设置面板证书路径: $CF_Domain"
            echo ""
            LOGI "  - 证书文件: $webCertFile"
            echo ""
            LOGI "  - 私钥文件: $webKeyFile"
            echo ""
            echo -e "${green}登录访问面板URL: https://${CF_Domain}:${existing_port}${green}${existing_webBasePath}${plain}"
            echo ""
            echo -e "${green}PS：若您要登录访问面板，请复制上面的地址到浏览器打开即可${plain}"
            echo ""
            restart    # 自动重启面板以应用证书
        else
            LOGE "错误：未找到域名的证书或私钥文件: $CF_Domain。"
        fi

    else
        show_menu
    fi
}

warp_cloudflare() {
    echo -e "${green}\t1.${plain} 安装 WARP socks5 代理"
    echo -e "${green}\t2.${plain} 账户类型 (free, plus, team)"
    echo -e "${green}\t3.${plain} 开启 / 关闭 WireProxy"
    echo -e "${green}\t4.${plain} 卸载 WARP"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请输入选项: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        bash <(curl -sSL ${GH_PROXY}https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh)
        ;;
    2)
        warp a
        ;;
    3)
        warp y
        ;;
    4)
        warp u
        ;;
    *) echo "无效选项" ;;
    esac
}

# --------- 【订阅转换】模块 ---------- 
subconverter() {
echo ""
echo -e "${green}==============================================="
echo -e "〔订阅转换〕一键部署"
echo -e "1. 自动安装/部署 Nginx"
echo -e "2. 自动调用面板的证书"
echo -e "3. 自动部署 Sublink 服务"
echo -e "4. 自动配置 Nginx 反向代理"
echo -e "5. 可直观在前端页面配置订阅"
echo -e "作者：〔X-Panel 面板〕专属定制"
echo -e "===============================================${plain}"
echo ""
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
    echo -e "${green}面板已安装证书采用SSL保护${plain}"
    echo ""
    domain=$(basename "$(dirname "$existing_cert")")
    echo -e "${green}------------->>>>接下来进行sublink订阅转换服务的安装  ........${plain}"
    sleep 3
    echo ""
else
    echo -e "${red}警告：未找到证书和密钥，面板不安全！${plain}"
    echo ""
    echo -e "${green}------->>>>且不能安装sublink订阅转换服务<<<<-------${plain}"
    echo ""
    sleep 5
    exit 1
fi

# --------- 安装/部署sublink服务 ----------

bash <(curl -Ls ${GH_PROXY}https://raw.githubusercontent.com/xeefei/sublink/main/install.sh)


# --------- 安装 Nginx ----------
if ! command -v nginx &>/dev/null; then
    echo -e "${yellow}-------------->>>>>>>>未检测到 Nginx，正在安装...${plain}"
    apt update && apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
else
    echo -e "${green}检测到 Nginx 已安装，跳过安装步骤${plain}"
fi

# --------- 拷贝X-Panel已有证书到 Nginx ----------
mkdir -p /etc/nginx/ssl
acme_path="/root/.acme.sh/${domain}_ecc"

cp "${acme_path}/fullchain.cer" "/etc/nginx/ssl/${domain}.cer"
cp "${acme_path}/${domain}.key" "/etc/nginx/ssl/${domain}.key"


# --------- 配置 Nginx 反向代理 ----------
NGINX_CONF="/etc/nginx/conf.d/sublink.conf"
cat > $NGINX_CONF <<EOF
server {
    listen 15268 ssl http2;
    server_name ${domain};

    # 证书路径（从 acme.sh 复制到 /etc/nginx/ssl/ 下）
    ssl_certificate     /etc/nginx/ssl/${domain}.cer;
    ssl_certificate_key /etc/nginx/ssl/${domain}.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# 重载 nginx，让新证书生效
sleep 1
systemctl reload nginx
sleep 2

# --------- 使用 sed 替换 ExecStart 行，添加启动参数 ----------
sudo sed -i "/^ExecStart=/ s|$| run --port 8000|" "/etc/systemd/system/sublink.service"
# 重新加载 systemd 守护进程
sudo systemctl daemon-reload
# 重启 sublink 服务
sudo systemctl restart sublink


# --------- 开放防火墙端口 ----------
echo ""
echo -e "${yellow}请务必手动放行${plain}${red} 8000 和 15268 ${yellow}端口！！${plain}"
echo ""

# --------- 完成提示 ----------
echo ""
echo -e "${green}【订阅转换模块】安装完成！！！${plain}"
echo ""
echo -e "${green}登录用户名：admin，密码：123456，请进后台自行修改${plain}"
echo ""
echo -e "${green}Web 界面访问地址：https://${domain}:15268${plain}"
echo ""
echo -e "${green}若要登录前端网页使用【订阅转换】，请直接复制以上地址${plain}"
echo ""
echo -e "${green}接下来流程会进入〔X-Panel面板〕x-ui 菜单项${plain}"
sleep 8
echo ""
# --------- 返回菜单 ----------
show_menu
}

run_speedtest() {
    # Check if Speedtest is already installed
    if ! command -v speedtest &>/dev/null; then
        # If not installed, install it
        local pkg_manager=""
        local speedtest_install_script=""

        if command -v dnf &>/dev/null; then
            pkg_manager="dnf"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
        elif command -v yum &>/dev/null; then
            pkg_manager="yum"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh"
        elif command -v apt-get &>/dev/null; then
            pkg_manager="apt-get"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
        elif command -v apt &>/dev/null; then
            pkg_manager="apt"
            speedtest_install_script="https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh"
        fi

        if [[ -z $pkg_manager ]]; then
            echo "错误：找不到包管理器。 您可能需要手动安装 Speedtest"
            return 1
        else
            curl -s $speedtest_install_script | bash
            $pkg_manager install -y speedtest
        fi
    fi

    # Run Speedtest
    speedtest
}


iplimit_main() {
    echo -e "\n${green}\t1.${plain} 安装 Fail2ban 并配置 IP 限制"
    echo -e "${green}\t2.${plain} 更改禁止期限"
    echo -e "${green}\t3.${plain} 解禁所有 IP"
    echo -e "${green}\t4.${plain} 查看日志"
    echo -e "${green}\t5.${plain} Fail2ban 状态"
    echo -e "${green}\t6.${plain} 重启 Fail2ban"
    echo -e "${green}\t7.${plain} 卸载 Fail2ban"
    echo -e "${green}\t0.${plain} 返回主菜单"
    read -p "请输入选项: " choice
    case "$choice" in
    0)
        show_menu
        ;;
    1)
        confirm "继续安装 Fail2ban 和 IP 限制?" "y"
        if [[ $? == 0 ]]; then
            install_iplimit
        else
            iplimit_main
        fi
        ;;
    2)
        read -rp "请输入新的禁令持续时间（以分钟为单位）[默认 30]: " NUM
        if [[ $NUM =~ ^[0-9]+$ ]]; then
            create_iplimit_jails ${NUM}
            systemctl restart fail2ban
        else
            echo -e "${red}${NUM} 不是一个数字！ 请再试一次.${plain}"
        fi
        iplimit_main
        ;;
    3)
        confirm "继续解除所有人的 IP 限制禁令?" "y"
        if [[ $? == 0 ]]; then
            fail2ban-client reload --restart --unban 3x-ipl
            truncate -s 0 "${iplimit_banned_log_path}"
            echo -e "${green}所有用户已成功解封${plain}"
            iplimit_main
        else
            echo -e "${yellow}已取消${plain}"
        fi
        iplimit_main
        ;;
    4)
        show_banlog
        ;;
    5)
        service fail2ban status
        ;;
    6)
        systemctl restart fail2ban
        ;;
    7)
        remove_iplimit
        ;;
    *) echo "无效选项" ;;
    esac
}

install_iplimit() {
    if ! command -v fail2ban-client &>/dev/null; then
        echo -e "${green}未安装 Fail2ban。正在安装...!${plain}\n"

        # Check the OS and install necessary packages
        case "${release}" in
        ubuntu)
            apt-get update
            if [[ "${os_version}" -ge 24 ]]; then
                apt-get install python3-pip -y
                python3 -m pip install pyasynchat --break-system-packages
            fi
            apt-get install fail2ban -y
            ;;
        debian)
            apt-get update
            if [ "$os_version" -ge 12 ]; then
                apt-get install -y python3-systemd
            fi
            apt-get install -y fail2ban
            ;;
        armbian)
            apt-get update && apt-get install fail2ban -y
            ;;
        centos | almalinux | rocky | oracle | anolis)
            yum update -y && yum install epel-release -y
            yum -y install fail2ban
            ;;
        fedora)
            dnf -y update && dnf -y install fail2ban
            ;;
        arch | manjaro | parch)
            pacman -Syu --noconfirm fail2ban
            ;;
        *)
            echo -e "${red}不支持的操作系统，请检查脚本并手动安装必要的软件包.${plain}\n"
            exit 1
            ;;
        esac

        if ! command -v fail2ban-client &>/dev/null; then
            echo -e "${red}Fail2ban 安装失败${plain}\n"
            exit 1
        fi

        echo -e "${green}Fail2ban 安装成功!${plain}\n"
    else
        echo -e "${yellow}Fail2ban 已安装${plain}\n"
    fi

    echo -e "${green}配置 IP 限制中...${plain}\n"

    # make sure there's no conflict for jail files
    iplimit_remove_conflicts

    # Check if log file exists
    if ! test -f "${iplimit_banned_log_path}"; then
        touch ${iplimit_banned_log_path}
    fi

    # Check if service log file exists so fail2ban won't return error
    if ! test -f "${iplimit_log_path}"; then
        touch ${iplimit_log_path}
    fi

    # Create the iplimit jail files
    # we didn't pass the bantime here to use the default value
    create_iplimit_jails

    # Launching fail2ban
    if ! systemctl is-active --quiet fail2ban; then
        systemctl start fail2ban
        systemctl enable fail2ban
    else
        systemctl restart fail2ban
    fi
    systemctl enable fail2ban

    echo -e "${green}IP 限制安装并配置成功!${plain}\n"
    before_show_menu
}

remove_iplimit() {
    echo -e "${green}\t1.${plain} 仅删除 IP 限制配置"
    echo -e "${green}\t2.${plain} 卸载 Fail2ban 和 IP 限制"
    echo -e "${green}\t0.${plain} 终止"
    read -p "请输入选项: " num
    case "$num" in
    1)
        rm -f /etc/fail2ban/filter.d/3x-ipl.conf
        rm -f /etc/fail2ban/action.d/3x-ipl.conf
        rm -f /etc/fail2ban/jail.d/3x-ipl.conf
        systemctl restart fail2ban
        echo -e "${green}IP 限制成功解除!${plain}\n"
        before_show_menu
        ;;
    2)
        rm -rf /etc/fail2ban
        systemctl stop fail2ban
        case "${release}" in
        ubuntu | debian | armbian)
            apt-get remove -y fail2ban
            apt-get purge -y fail2ban -y
            apt-get autoremove -y
            ;;
        centos | almalinux | rocky | oracle | anolis)
            yum remove fail2ban -y
            yum autoremove -y
            ;;
        fedora)
            dnf remove fail2ban -y
            dnf autoremove -y
            ;;
        arch | manjaro)
            pacman -Rns --noconfirm fail2ban
            ;;
        *)
            echo -e "${red}不支持的操作系统，请手动卸载 Fail2ban.${plain}\n"
            exit 1
            ;;
        esac
        echo -e "${green}Fail2ban 和 IP 限制已成功删除!${plain}\n"
        before_show_menu
        ;;
    0)
        echo -e "${yellow}已取消${plain}\n"
        iplimit_main
        ;;
    *)
        echo -e "${red}无效选项。 请选择一个有效的选项。${plain}\n"
        remove_iplimit
        ;;
    esac
}

show_banlog() {
    local system_log="/var/log/fail2ban.log"

    echo -e "${green}正在检查禁止日志...${plain}\n"

    if ! systemctl is-active --quiet fail2ban; then
        echo -e "${red}Fail2ban 服务未运行！${plain}\n"
        return 1
    fi

    if [[ -f "$system_log" ]]; then
        echo -e "${green}来自 fail2ban.log 的最近系统禁止活动:${plain}"
        grep "3x-ipl" "$system_log" | grep -E "Ban|Unban" | tail -n 10 || echo -e "${yellow}未发现近期系统禁止活动${plain}"
        echo ""
    fi

    if [[ -f "${iplimit_banned_log_path}" ]]; then
        echo -e "${green}3X-IPL禁止日志文件条目:${plain}"
        if [[ -s "${iplimit_banned_log_path}" ]]; then
            grep -v "INIT" "${iplimit_banned_log_path}" | tail -n 10 || echo -e "${yellow}未找到禁止条目${plain}"
        else
            echo -e "${yellow}禁止日志文件为空${plain}"
        fi
    else
        echo -e "${red}未找到禁止日志文件: ${iplimit_banned_log_path}${plain}"
    fi

    echo -e "\n${green}目前的限制情况:${plain}"
    fail2ban-client status 3x-ipl || echo -e "${yellow}无法获取限制状态${plain}"
}

create_iplimit_jails() {
    # Use default bantime if not passed => 30 minutes
    local bantime="${1:-30}"

    # Uncomment 'allowipv6 = auto' in fail2ban.conf
    sed -i 's/#allowipv6 = auto/allowipv6 = auto/g' /etc/fail2ban/fail2ban.conf

    # On Debian 12+ fail2ban's default backend should be changed to systemd
    if [[  "${release}" == "debian" && ${os_version} -ge 12 ]]; then
        sed -i '0,/action =/s/backend = auto/backend = systemd/' /etc/fail2ban/jail.conf
    fi

    cat << EOF > /etc/fail2ban/jail.d/3x-ipl.conf
[3x-ipl]
enabled=true
backend=auto
filter=3x-ipl
action=3x-ipl
logpath=${iplimit_log_path}
maxretry=2
findtime=32
bantime=${bantime}m
EOF

    cat << EOF > /etc/fail2ban/filter.d/3x-ipl.conf
[Definition]
datepattern = ^%%Y/%%m/%%d %%H:%%M:%%S
failregex   = \[LIMIT_IP\]\s*Email\s*=\s*<F-USER>.+</F-USER>\s*\|\|\s*SRC\s*=\s*<ADDR>
ignoreregex =
EOF

    cat << EOF > /etc/fail2ban/action.d/3x-ipl.conf
[INCLUDES]
before = iptables-allports.conf

[Definition]
actionstart = <iptables> -N f2b-<name>
              <iptables> -A f2b-<name> -j <returntype>
              <iptables> -I <chain> -p <protocol> -j f2b-<name>

actionstop = <iptables> -D <chain> -p <protocol> -j f2b-<name>
             <actionflush>
             <iptables> -X f2b-<name>

actioncheck = <iptables> -n -L <chain> | grep -q 'f2b-<name>[ \t]'

actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>
            echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   BAN   [Email] = <F-USER> [IP] = <ip> banned for <bantime> seconds." >> ${iplimit_banned_log_path}

actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>
              echo "\$(date +"%%Y/%%m/%%d %%H:%%M:%%S")   UNBAN   [Email] = <F-USER> [IP] = <ip> unbanned." >> ${iplimit_banned_log_path}

[Init]
name = default
protocol = tcp
chain = INPUT
EOF

    echo -e "${green}创建的 IP Limit 限制文件禁止时间为 ${bantime} 分钟。${plain}"
}

iplimit_remove_conflicts() {
    local jail_files=(
        /etc/fail2ban/jail.conf
        /etc/fail2ban/jail.local
    )

    for file in "${jail_files[@]}"; do
        # Check for [3x-ipl] config in jail file then remove it
        if test -f "${file}" && grep -qw '3x-ipl' ${file}; then
            sed -i "/\[3x-ipl\]/,/^$/d" ${file}
            echo -e "${yellow}消除系统环境中 [3x-ipl] 的冲突 (${file})!${plain}\n"
        fi
    done
}

show_usage() {
    echo -e "         ---------------------"
    echo -e "         |${green}X-Panel 控制菜单用法 ${plain}|${plain}"
    echo -e "         |  ${yellow}一个更好的面板   ${plain}|${plain}"   
    echo -e "         | ${yellow}基于Xray Core构建 ${plain}|${plain}"  
    echo -e "--------------------------------------------"
    echo -e "x-ui              - 进入管理脚本"
    echo -e "x-ui start        - 启动 X-Panel 面板"
    echo -e "x-ui stop         - 关闭 X-Panel 面板"
    echo -e "x-ui restart      - 重启 X-Panel 面板"
    echo -e "x-ui status       - 查看 X-Panel 状态"
    echo -e "x-ui settings     - 查看当前设置信息"
    echo -e "x-ui enable       - 启用 X-Panel 开机启动"
    echo -e "x-ui disable      - 禁用 X-Panel 开机启动"
    echo -e "x-ui log          - 查看 X-Panel 运行日志"
    echo -e "x-ui banlog       - 检查 Fail2ban 禁止日志"
    echo -e "x-ui update       - 更新 X-Panel 面板"
    echo -e "x-ui custom       - 自定义 X-Panel 版本"
    echo -e "x-ui install      - 安装 X-Panel 面板"
    echo -e "x-ui uninstall    - 卸载 X-Panel 面板"
    echo -e "--------------------------------------------"
}

show_menu() {
    echo -e "
——————————————————————
  ${green}X-Panel 面板管理脚本${plain}
  ${yellow}  一个更好的面板${plain}
  ${yellow} 基于Xray Core构建${plain}
——————————————————————
  ${green}0.${plain} 退出脚本
  ${green}1.${plain} 安装面板
  ${green}2.${plain} 更新面板
  ${green}3.${plain} 更新菜单项
  ${green}4.${plain} 自定义版本
  ${green}5.${plain} 卸载面板
——————————————————————
  ${green}6.${plain} 重置用户名、密码
  ${green}7.${plain} 修改访问路径
  ${green}8.${plain} 重置面板设置
  ${green}9.${plain} 修改面板端口
  ${green}10.${plain} 查看面板设置
——————————————————————
  ${green}11.${plain} 启动面板
  ${green}12.${plain} 关闭面板
  ${green}13.${plain} 重启面板
  ${green}14.${plain} 检查面板状态
  ${green}15.${plain} 检查面板日志
——————————————————————
  ${green}16.${plain} 启用开机启动
  ${green}17.${plain} 禁用开机启动
——————————————————————
  ${green}18.${plain} SSL 证书管理
  ${green}19.${plain} CF SSL 证书
  ${green}20.${plain} IP 限制管理
  ${green}21.${plain} 防火墙管理
——————————————————————
  ${green}22.${plain} 启用 BBR 
  ${green}23.${plain} 更新 Geo 文件
  ${green}24.${plain} Speedtest by Ookla
  ${green}25.${plain} 安装订阅转换 
——————————————————————
  ${green}若在使用过程中有任何问题${plain}
  ${yellow}请加入〔X-Panel面板〕交流群${plain}
  ${red}https://t.me/XUI_CN ${yellow}截图进行反馈${plain}
  ${green}〔X-Panel面板〕项目地址${plain}
  ${yellow}https://github.com/xeefei/x-panel${plain}
  ${green}详细〔安装配置〕教程${plain}
  ${yellow}https://xeefei.blogspot.com/2025/09/x-panel.html${plain}
——————————————————————

-------------->>>>>>>赞 助 推 广 区<<<<<<<<-------------------

${green}1、搬瓦工GIA高端线路：${yellow}https://bandwagonhost.com/aff.php?aff=75015${plain}

${green}2、Dmit高端GIA线路：${yellow}https://www.dmit.io/aff.php?aff=9326${plain}

${green}3、Gomami亚太顶尖优化线路：${yellow}https://gomami.io/aff.php?aff=174${plain}

${green}4、ISIF优质亚太优化线路：${yellow}https://cloud.isif.net/login?affiliation_code=333${plain}

${green}5、Bagevm优质落地鸡（原生IP全解锁）：${yellow}https://www.bagevm.com/aff.php?aff=754${plain}

${green}6、白丝云〔4837线路〕实惠量大管饱：${yellow}https://cloudsilk.io/aff.php?aff=706${plain}

${green}7、RackNerd极致性价比机器：${yellow}https://my.racknerd.com/aff.php?aff=15268&pid=912${plain}

----------------------------------------------
"
    show_status
    echo && read -p "请输入选项 [0-25]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        check_uninstall && install
        ;;
    2)
        check_install && update
        ;;
    3)
        check_install && update_menu
        ;;
    4)
        check_install && custom_version
        ;;
    5)
        check_install && uninstall
        ;;
    6)
        check_install && reset_user
        ;;
    7)
        check_install && reset_webbasepath
        ;;
    8)
        check_install && reset_config
        ;;
    9)
        check_install && set_port
        ;;
    10)
        check_install && check_config
        ;;
    11)
        check_install && start
        ;;
    12)
        check_install && stop
        ;;
    13)
        check_install && restart
        ;;
    14)
        check_install && status
        ;;
    15)
        check_install && show_log
        ;;
    16)
        check_install && enable
        ;;
    17)
        check_install && disable
        ;;
    18)
        ssl_cert_issue_main
        ;;
    19)
        ssl_cert_issue_CF
        ;;
    20)
        iplimit_main
        ;;
    21)
        firewall_menu
        ;;
    22)
        bbr_menu
        ;;
    23)
        update_geo
        ;;
    24)
        run_speedtest
        ;;
    25)
        subconverter
        ;;
    *)
        LOGE "请输入正确的数字选项 [0-25]"
        ;;
    esac
}

if [[ $# > 0 ]]; then
    case $1 in
    "start")
        check_install 0 && start 0
        ;;
    "stop")
        check_install 0 && stop 0
        ;;
    "restart")
        check_install 0 && restart 0
        ;;
    "status")
        check_install 0 && status 0
        ;;
    "settings")
        check_install 0 && check_config 0
        ;;
    "enable")
        check_install 0 && enable 0
        ;;
    "disable")
        check_install 0 && disable 0
        ;;
    "log")
        check_install 0 && show_log 0
        ;;
    "banlog")
        check_install 0 && show_banlog 0
        ;;
    "update")
        check_install 0 && update 0
        ;;
    "custom")
        check_install 0 && custom_version 0
        ;;
    "install")
        check_uninstall 0 && install 0
        ;;
    "uninstall")
        check_install 0 && uninstall 0
        ;;
    "subconverter")
        check_install 0 && subconverter 0
        ;;    
    *) show_usage ;;
    esac
else
    show_menu
fi
