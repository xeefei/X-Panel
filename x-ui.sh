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
echo -e "${green}当前代理面板的版本为: ${red}〔X-Panel 付费Pro版〕v${xui_version}${plain}"
echo ""
echo -e "${yellow}〔X-Panel 付费Pro版〕最新版为---------->>> ${last_version}${plain}"

os_version=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)

if [[ "${release}" == "centos" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red} 请使用 CentOS 8 或更高版本 ${plain}\n" && exit 1
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
    # 【新代码】指向你服务器上公开的 install.sh 启动器
    bash <(curl -Ls https://auth.x-panel.vip/install.sh)
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
    # 【新代码】指向你服务器上公开的 install.sh 启动器
    bash <(curl -Ls https://auth.x-panel.vip/install.sh)
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
    
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/xeefei/x-panel-pro/main/x-ui.sh
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
    echo "输入面板版本 (例: v25.11.11):"
    read panel_version

    if [ -z "$panel_version" ]; then
        echo "面板版本不能为空。"
        exit 1
    fi

    download_link="https://raw.githubusercontent.com/xeefei/x-panel-pro/master/install.sh"

    # Use the entered panel version in the download link
    install_command="bash <(curl -Ls $download_link) v$panel_version"

    echo "下载并安装〔X-Panel 付费Pro版〕 $panel_version..."
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
    echo ""
    echo -e "${green}bash <(curl -Ls https://raw.githubusercontent.com/xeefei/x-panel/master/install.sh)${plain}"
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
    echo ""
    echo -e "面板登录密码已重置为：${green} ${config_password} ${plain}"
    echo ""
    echo -e "${green} 请使用新的登录用户名和密码访问 X-Panel-Pro 面板。也请记住它们！${plain}"
    echo ""
    confirm_restart
}

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

reset_webbasepath() {
    echo -e "${yellow}修改访问路径${plain}"
    echo ""
    
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
    echo ""
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
    echo ""
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
        echo ""
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
    centos | almalinux | rocky | oracle)
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
    wget -O /usr/bin/x-ui -N --no-check-certificate https://github.com/xeefei/x-panel-pro/raw/main/x-ui.sh
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
    echo -e "${green}\t2.${plain} 允许的端口列表"
    echo -e "${green}\t3.${plain} 从列表中删除端口"
    echo -e "${green}\t4.${plain} 禁用 ufw 防火墙"
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
        echo -e "${green}ufw 防火墙未安装，正在安装......${plain}"
        apt-get update
        apt-get install -y ufw
        echo ""
    else
        echo ""
        echo -e "${green}ufw 防火墙已安装${plain}"
        echo ""
    fi

    # Check if the firewall is inactive
    if ufw status | grep -q "Status: active"; then
        echo -e "${yellow}ufw 防火墙已激活${plain}"
        echo ""
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
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat
    wget -N https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
    wget -O geoip_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_IR.dat -N https://github.com/chocolate4u/Iran-v2ray-rules/releases/latest/download/geosite.dat
    wget -O geoip_VN.dat https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geoip.dat
    wget -O geosite_VN.dat https://github.com/vuong2023/vn-v2ray-rules/releases/latest/download/geosite.dat
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
        echo ""
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
    
    # 签发前：智能检测 Nginx，若存在且运行中则临时停止以释放 80 端口
    if command -v nginx &>/dev/null && systemctl is-active --quiet nginx; then
        LOGI "检测到 Nginx 正在运行，为避免 80 端口冲突，正在临时停止 Nginx..."
        systemctl stop nginx
    fi
    systemctl stop x-ui >/dev/null 2>&1
    
    if ! ~/.acme.sh/acme.sh --issue --standalone -d $DOMAIN --server $CA_SERVER --force; then
        LOGE "❌ 证书申请失败！"
        LOGE "请检查：1、域名解析是否正确指向本机 IP。2、80 端口是否开放且未被占用。"
        # 失败尝试重启 x-ui，若 Nginx 存在则恢复启动
        systemctl start x-ui >/dev/null 2>&1
        if command -v nginx &>/dev/null; then
            systemctl start nginx >/dev/null 2>&1
        fi
        return 1
    fi

# --- 7. 安装证书到标准路径 ---
# 直接创建 x-ui 标准目录结构，
    local certPath="/root/cert/${DOMAIN}"
    if [ ! -d "$certPath" ]; then
        mkdir -p "$certPath"
    fi
    
    LOGI "申请成功！正在安装证书到: $certPath"
    
    # x-ui 是系统服务，使用自适应动态钩子（Smart Hook）更稳妥
    local smartPreHook='if command -v nginx &>/dev/null && systemctl is-active --quiet nginx; then systemctl stop nginx >/dev/null 2>&1; touch /tmp/xpanel_nginx_stopped_by_acme; fi'
    local smartPostHook='if [ -f /tmp/xpanel_nginx_stopped_by_acme ]; then systemctl start nginx >/dev/null 2>&1; rm -f /tmp/xpanel_nginx_stopped_by_acme; fi'
    local reloadCmd="systemctl restart x-ui" 
    
    ~/.acme.sh/acme.sh --installcert -d $DOMAIN \
        --key-file       "${certPath}/privkey.pem" \
        --fullchain-file "${certPath}/fullchain.pem" \
        --pre-hook       "${smartPreHook}" \
        --post-hook      "${smartPostHook}" \
        --reloadcmd      "${reloadCmd}"
        
    if [ $? -eq 0 ]; then
        LOGI "✅ 证书安装命令执行成功！"

# --- 关键修复：强制在系统中注册并写入 crontab 自动续签定时任务 ---
        ~/.acme.sh/acme.sh --install-cronjob >/dev/null 2>&1

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
            # 恢复 x-ui 运行，避免断联，若 Nginx 存在则恢复启动
            systemctl start x-ui >/dev/null 2>&1
            if command -v nginx &>/dev/null; then
                systemctl start nginx >/dev/null 2>&1
            fi
            return 1
        fi
    else
        LOGE "证书安装步骤失败，请检查日志。"
        systemctl start x-ui >/dev/null 2>&1
        if command -v nginx &>/dev/null; then
            systemctl start nginx >/dev/null 2>&1
        fi
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

    # 安装 socat 和 dnsutils/bind-utils (用于 dig)，并同时补全 cron 定时服务保证自动续签
    case "${release}" in
    ubuntu | debian | armbian)
        # 添加了 dnsutils 用于 dig 命令，并加入了 cron
        apt update && apt install socat dnsutils cron -y
        systemctl enable cron >/dev/null 2>&1
        systemctl start cron >/dev/null 2>&1
        ;;
    centos | rhel | almalinux | rocky | ol)
        # 添加了 bind-utils 用于 dig 命令，并加入了 cronie
        yum -y update && yum -y install socat bind-utils cronie
        systemctl start crond && systemctl enable crond
        ;;
    fedora | amzn | virtuozzo)
        # 添加了 bind-utils 用于 dig 命令，并加入了 cronie
        dnf -y update && dnf -y install socat bind-utils cronie
        systemctl start crond && systemctl enable crond
        ;;
    arch | manjaro | parch)
        # 添加了 dnsutils 用于 dig 命令
        pacman -Sy --noconfirm socat dnsutils cron
        systemctl enable cron >/dev/null 2>&1
        systemctl start cron >/dev/null 2>&1
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

    # 签发前：智能检测 Nginx，若存在且运行中则临时停止以释放 80 端口
    if command -v nginx &>/dev/null && systemctl is-active --quiet nginx; then
        LOGI "检测到 Nginx 正在运行，为避免 80 端口冲突，正在临时停止 Nginx..."
        systemctl stop nginx
    fi

    # 签发证书
    echo ""
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d ${domain} --listen-v6 --standalone --httpport ${WebPort} --force
    if [ $? -ne 0 ]; then
        LOGE "签发证书失败，请检查日志。"
        rm -rf ~/.acme.sh/${domain}
        # 失败时若 Nginx 存在则恢复启动
        if command -v nginx &>/dev/null; then
            systemctl start nginx >/dev/null 2>&1
        fi
        exit 1
    else
        LOGE "签发证书成功，正在安装证书..."
    fi

    # ---  自动设置自适应动态钩子（Smart Hook） ---
    echo ""
    local smartPreHook='if command -v nginx &>/dev/null && systemctl is-active --quiet nginx; then systemctl stop nginx >/dev/null 2>&1; touch /tmp/xpanel_nginx_stopped_by_acme; fi'
    local smartPostHook='if [ -f /tmp/xpanel_nginx_stopped_by_acme ]; then systemctl start nginx >/dev/null 2>&1; rm -f /tmp/xpanel_nginx_stopped_by_acme; fi'
    reloadCmd="systemctl restart x-ui"
    LOGI "ACME 的【自适应智能钩子】已自动配置（支持后期动态安装或卸载 Nginx）"
    
    # 安装证书
    echo ""
    ~/.acme.sh/acme.sh --installcert -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem \
        --pre-hook "${smartPreHook}" \
        --post-hook "${smartPostHook}" \
        --reloadcmd "${reloadCmd}"

    echo ""
    if [ $? -ne 0 ]; then
        LOGE "安装证书失败，正在退出。"
        rm -rf ~/.acme.sh/${domain}
        if command -v nginx &>/dev/null; then
            systemctl start nginx >/dev/null 2>&1
        fi
        exit 1
    else
        LOGI "安装证书成功，正在启用自动续订..."
    fi

# --- 关键修复：强制在系统中注册并写入 crontab 自动续签定时任务 ---
    ~/.acme.sh/acme.sh --install-cronjob >/dev/null 2>&1

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

        # --- 自动设置自适应动态钩子（Smart Hook） ---
        echo ""
        local smartPreHook='if command -v nginx &>/dev/null && systemctl is-active --quiet nginx; then systemctl stop nginx >/dev/null 2>&1; touch /tmp/xpanel_nginx_stopped_by_acme; fi'
        local smartPostHook='if [ -f /tmp/xpanel_nginx_stopped_by_acme ]; then systemctl start nginx >/dev/null 2>&1; rm -f /tmp/xpanel_nginx_stopped_by_acme; fi'
        reloadCmd="systemctl restart x-ui"
        LOGI "ACME 的【自适应智能钩子】已自动配置（支持后期动态安装或卸载 Nginx）"
        echo ""

        # 执行“安装证书”流程
        echo ""
        ~/.acme.sh/acme.sh --installcert -d ${CF_Domain} -d *.${CF_Domain} \
            --key-file ${certPath}/privkey.pem \
            --fullchain-file ${certPath}/fullchain.pem \
            --pre-hook "${smartPreHook}" \
            --post-hook "${smartPostHook}" \
            --reloadcmd "${reloadCmd}"
        
        echo ""
        if [ $? -ne 0 ]; then
            LOGE "证书安装失败，脚本正在退出..."
            exit 1
        else
            LOGI "证书安装成功，正在开启自动更新..."
        fi

# --- 关键修复：强制在系统中注册并写入 crontab 自动续签定时任务 ---
    ~/.acme.sh/acme.sh --install-cronjob >/dev/null 2>&1

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
        bash <(curl -sSL https://raw.githubusercontent.com/hamid-gh98/x-ui-scripts/main/install_warp_proxy.sh)
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
echo -e "作者：〔X-Panel 付费Pro版〕专属定制"
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

bash <(curl -Ls https://raw.githubusercontent.com/xeefei/sublink/main/install.sh)


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
        centos | almalinux | rocky | oracle)
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
        centos | almalinux | rocky | oracle)
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

# 【中文注释】：这是新添加的“网页版SSH工具”安装函数
# 1. 自动从 GitHub API 获取最新版本
# 2. 完整移植了 .go 文件中的 UFW、Nginx 和 systemd 逻辑
install_sshwifty() {
    echo "=== 开始安装 Sshwifty (网页版SSH) ==="
    
    # 0.a 提取 Go 里的域名获取逻辑
    # 【中文注释】：首先检查面板是否已配置 SSL 证书，以便获取域名
    local existing_cert=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'cert: .+' | awk '{print $2}')
    local existing_key=$(/usr/local/x-ui/x-ui setting -getCert true | grep -Eo 'key: .+' | awk '{print $2}')
    local domain=""
    local ACME_PATH=""

    if [[ -n "$existing_cert" && -n "$existing_key" ]]; then
        domain=$(basename "$(dirname "$existing_cert")")
        # 【中文注释】：从 .go 文件中获取 acme 路径逻辑
        ACME_PATH="/root/.acme.sh/${domain}_ecc"
        LOGI "获取到用于 Nginx 配置的域名: ${domain}"
        LOGI "将使用证书路径: ${ACME_PATH}"
    else
        LOGE "Sshwifty 安装失败：无法获取面板域名以配置 Nginx。"
        LOGE "请先为面板申请 SSL 证书 (菜单项 18 或 19)。"
        return 1 # 中止安装
    fi
    
    # 【中文注释】：检查证书文件是否存在，这是 .go 文件中的关键检查
    local CERT_FILE="${ACME_PATH}/fullchain.cer"
    local KEY_FILE="${ACME_PATH}/${domain}.key"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        LOGE "⚠️ **警告：Nginx 配置失败**"
        LOGE "错误: 找不到 Nginx 所需的 SSL 证书！"
        LOGE "检查路径: ${CERT_FILE}"
        LOGE "检查路径: ${KEY_FILE}"
        LOGE "Sshwifty 服务将安装，但 Nginx 反代将失败。"
        # 【中文注释】：我们继续安装，但 Nginx 会跳过
    fi

    # 0.b 提取 Go 里的 UFW (端口放行) 逻辑
    LOGI "正在为 Sshwifty 服务配置防火墙..."
    PORTS_TO_OPEN="8182 8188" # Sshwifty 自身端口和 Nginx 代理端口
    DEFAULT_PORTS="22 80 443 13688 8443" # 面板运行所需的基础端口
    
    if ! command -v ufw &>/dev/null; then
        LOGI "ufw 防火墙未安装，正在安装..."
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw >/dev/null
        if [ $? -ne 0 ]; then LOGE "ufw 安装失败或权限不足。"; return 1; fi
    fi

    LOGI "正在检查并放行基础服务端口: $DEFAULT_PORTS"
    for p in $DEFAULT_PORTS; do
        if ! ufw status | grep -qw "$p/tcp"; then
            LOGI "端口 $p/tcp 未放行，正在添加规则..."
            ufw allow $p/tcp >/dev/null
            if [ $? -ne 0 ]; then LOGE "ufw 端口 $p 放行失败。"; return 1; fi
        fi
    done
    LOGI "基础服务端口检查完毕。"

    LOGI "正在检查并放行 Sshwifty 服务端口: $PORTS_TO_OPEN"
    for port in $PORTS_TO_OPEN; do
        if ! ufw status | grep -qw "$port"; then
            LOGI "正在执行 ufw allow $port..."
            ufw allow $port >/dev/null
            if [ $? -ne 0 ]; then LOGE "ufw 端口 $port 放行失败。"; return 1; fi
        fi
    done

    if ! ufw status | grep -q "Status: active"; then
        LOGI "ufw 状态：未激活。正在尝试激活..."
        ufw --force enable
        if [ $? -ne 0 ]; then LOGE "ufw 激活失败。"; return 1; fi
    fi
    LOGI "✅ 所有端口 ($DEFAULT_PORTS $PORTS_TO_OPEN) 已成功放行/检查。"

    # --- 从这里开始是 Go 脚本中的 shellCommand ---
    
    # 0. 检查权限和停止旧服务
    if [ "$EUID" -ne 0 ]; then
        LOGE "致命错误：安装脚本必须以 root 权限运行！"
        return 1
    fi

    if systemctl is-active --quiet sshwifty; then
        LOGI "检测到正在运行的 Sshwifty 服务，正在停止..."
        systemctl stop sshwifty
    fi

    # 1. 安装依赖
    LOGI "正在安装依赖: curl, wget, tar, jq..."
    # 【中文注释】：增加了 jq，用于更可靠地修改 json 配置文件
    DEPENDENCIES="curl wget tar jq"
    UNMET_DEPS=""
    for dep in $DEPENDENCIES; do
        if ! command -v $dep &>/dev/null; then 
            UNMET_DEPS="$UNMET_DEPS $dep"
        fi
    done

    if [ -n "$UNMET_DEPS" ]; then
        LOGI "【发现缺失依赖】: $UNMET_DEPS，尝试自动安装..."
        if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $UNMET_DEPS
            if [ $? -ne 0 ]; then LOGE "错误：使用 apt-get 安装依赖 $UNMET_DEPS 失败！"; return 1; fi
        elif command -v yum &>/dev/null; then
            yum install -y -q $UNMET_DEPS
            if [ $? -ne 0 ]; then LOGE "错误：使用 yum 安装依赖 $UNMET_DEPS 失败！"; return 1; fi
        else
            LOGE "致命错误: 无法自动安装依赖 ($UNMET_DEPS)。请手动安装后再试。"
            return 1
        fi
    fi
    LOGI "依赖检查与安装完成。"

    # 1.b 安装 Nginx
    if ! command -v nginx &>/dev/null; then
        LOGI "未检测到 Nginx，正在安装..."
        if command -v apt-get &>/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
            if [ $? -ne 0 ]; then LOGE "错误：使用 apt-get 安装 Nginx 失败！"; return 1; fi
        elif command -v yum &>/dev/null; then
            yum install -y -q nginx
            if [ $? -ne 0 ]; then LOGE "错误：使用 yum 安装 Nginx 失败！"; return 1; fi
        else
            LOGE "错误: 无法自动安装 nginx。请手动安装后再试。"
            return 1
        fi
        systemctl enable nginx
        systemctl start nginx
    else
        LOGI "检测到 Nginx 已安装，跳过安装步骤。"
    fi

    # 2. 【重大更新】：自动获取最新版本
    LOGI "正在从 GitHub API 获取 Sshwifty 最新版本..."
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/nirui/sshwifty/releases/latest" | grep "browser_download_url" | grep "linux_amd64.tar.gz" | cut -d '"' -f 4 | head -n 1)

    if [ -z "$DOWNLOAD_URL" ]; then
        LOGE "致命错误: 无法自动获取最新的 Sshwifty 下载地址。"
        LOGE "请检查您的 VPS 是否能访问 GitHub API (api.github.com)。"
        return 1
    fi
    
    FILENAME=$(basename "$DOWNLOAD_URL")
    LOGI "获取到最新下载地址: $DOWNLOAD_URL"
    TEMP_DIR="/tmp/sshwifty_install_$$"

    # 3. 下载并解压
    LOGI "正在下载 $FILENAME..."
    rm -rf $TEMP_DIR
    mkdir -p $TEMP_DIR
    # 【中文注释】：使用 curl -fsL 替代 wget，-f 失败时静默退出，-s 静默，-L 跟随跳转
    curl -fsL -o "$TEMP_DIR/$FILENAME" $DOWNLOAD_URL
    if [ $? -ne 0 ]; then 
        LOGE "致命错误: 下载 Sshwifty 失败！"
        rm -rf $TEMP_DIR
        return 1
    fi

    LOGI "正在解压文件..."
    tar -xzvf "$TEMP_DIR/$FILENAME" -C $TEMP_DIR
    if [ $? -ne 0 ]; then 
        LOGE "致命错误: 解压 Sshwifty 失败。文件可能已损坏。"
        rm -rf $TEMP_DIR
        return 1
    fi

    # 4. 复制可执行文件并授权
    INSTALL_PATH="/usr/local/bin/sshwifty"
    LOGI "正在安装可执行文件到 $INSTALL_PATH..."
    # 【中文注释】：在解压目录中查找可执行文件
    BINARY_FILE=$(find $TEMP_DIR -type f \( -name "sshwifty_linux_amd64" -o -name "sshwifty" \) | head -n 1)

    if [ ! -f "$BINARY_FILE" ]; then
        LOGE "致命错误: 在解压目录中未找到 Sshwifty 可执行文件 ($TEMP_DIR)。"
        rm -rf $TEMP_DIR
        return 1
    fi

    cp "$BINARY_FILE" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    LOGI "安装成功: $INSTALL_PATH"

    # 5. 生成默认配置文件 (保留 IP 修复逻辑)
    CONFIG_PATH="/etc/sshwifty.conf.json"
    if [ ! -f "$CONFIG_PATH" ]; then
        LOGI "正在创建默认配置文件: $CONFIG_PATH..."
        # 【中文注释】：在解压目录中查找示例配置文件
        EXAMPLE_CONFIG=$(find $TEMP_DIR -type f -name "*sshwifty.conf.example.json*" | head -n 1)
        if [ -f "$EXAMPLE_CONFIG" ]; then
            cp "$EXAMPLE_CONFIG" "$CONFIG_PATH"
        else
            # 【中文注释】：如果找不到，创建一个最小配置
            cat <<EOF > $CONFIG_PATH
{
    "Host": "127.0.0.1", 
    "Port": 8182,
    "Debug": false,
    "Title": "Sshwifty Web SSH"
}
EOF
        fi
        # 【中文注释】：确保 Host 正确设置为 127.0.0.1
        jq '.Host = "127.0.0.1"' $CONFIG_PATH > $CONFIG_PATH.tmp && mv $CONFIG_PATH.tmp $CONFIG_PATH
        LOGI "默认配置文件已创建并修正。"
    else
        LOGI "配置文件 $CONFIG_PATH 已存在，跳过创建。"
        # 【中文注释】：确保 Host 正确设置为 127.0.0.1
        jq '.Host = "127.0.0.1"' $CONFIG_PATH > $CONFIG_PATH.tmp && mv $CONFIG_PATH.tmp $CONFIG_PATH
        LOGI "确保 $CONFIG_PATH 监听 127.0.0.1 (使用 jq)"
    fi

    # 6. 创建 systemd 服务文件
    SERVICE_PATH="/etc/systemd/system/sshwifty.service"
    LOGI "正在创建 systemd 服务: $SERVICE_PATH..."
    cat <<EOF > $SERVICE_PATH
[Unit]
Description=Sshwifty - Web SSH Client
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_PATH --config $CONFIG_PATH
User=root
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    # 7. 重新加载、启用并启动服务
    LOGI "正在配置 systemd 服务 (开机自启)..."
    systemctl daemon-reload
    systemctl enable sshwifty
    systemctl restart sshwifty

    # 8. 清理临时文件
    LOGI "正在清理临时文件..."
    rm -rf $TEMP_DIR

    # 9. 检查服务状态
    if ! systemctl is-active --quiet sshwifty; then
        LOGE "致命错误: Sshwifty 服务启动失败！请检查 8182 端口是否被占用，或查看以下日志："
        journalctl -u sshwifty -n 20 --no-pager
        return 1
    fi
    LOGI "✅ Sshwifty (8182 端口) 启动成功。"

    # 10. 配置 Nginx 反向代理
    LOGI "=== 开始配置 Nginx 反向代理 (8188 -> 8182) ==="
    DOMAIN="${domain}" # <--- 这里使用我们之前获取的变量

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        LOGE "⚠️ **警告：Nginx 配置跳过**"
        LOGE "错误: 找不到 Nginx 所需的 SSL 证书！Sshwifty 服务已运行在 127.0.0.1:8182。"
    else
        # 【中文注释】：移植 Go 代码中的证书复制逻辑
        mkdir -p /etc/nginx/ssl
        cp "${CERT_FILE}" "/etc/nginx/ssl/${DOMAIN}.cer"
        cp "${KEY_FILE}" "/etc/nginx/ssl/${DOMAIN}.key"

        cat > /etc/nginx/conf.d/sshwifty-proxy.conf <<EOF
# --- Sshwifty (Web SSH) 反向代理配置 ---
server {
    listen 8188 ssl http2;
    server_name ${DOMAIN};
    # 【中文注释】：使用复制后的证书路径
    ssl_certificate       /etc/nginx/ssl/${DOMAIN}.cer;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:8182;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
        LOGI "正在重载 Nginx..."
        if ! systemctl reload nginx; then
            LOGE "错误: Nginx 重载失败。请检查配置。"
        fi
        LOGI "✅ Nginx 反向代理配置成功。"
    fi

    LOGI "=== Sshwifty 安装并启动成功! ==="
    
    # 【中文注释】：安装完成后向用户显示最终访问信息
    echo ""
    echo -e "${green}🎉 恭喜！【网页版SSH】模块已成功安装！${plain}"
    echo ""
    echo -e "${green}已自动为您配置 Nginx 反向代理。${plain}"
    echo ""
    echo -e "${green}您现在可以使用以下地址访问 Web 界面：${plain}"
    echo ""
    echo -e "🔗 ${yellow}登录地址: https://${DOMAIN}:8188${plain}"
    echo ""
    echo -e "${green}默认登录口令为： ${yellow}WEB_ACCESS_PASSWORD${plain}"
    echo ""
    echo -e "${green}(如果无法登录，请在 /etc/sshwifty.conf.json 中查看或设置口令)${plain}"
    echo ""
    
    before_show_menu
}

# 【中文注释】：这是新添加的“线路和IP检测”相关函数
ip_check() {
    # 【中文注释】：功能 1：检测 IP
    bash <(curl -Ls https://Check.Place) -I
    before_show_menu
}

route_check() {
    # 【中文注释】：功能 2：检测线路
    bash <(curl -Ls https://Check.Place) -N
    before_show_menu
}

check_place_menu() {
    # 【中文注释】：这是选项 27 的子菜单
    echo -e "
  ${green}线路和IP检测 (Check.Place)${plain}
  
  ${green}1.${plain} 检测 IP 质量
  ${green}2.${plain} 检测 线路/路由
  ——————————————————————
  ${green}0.${plain} 返回主菜单
  "
    read -p "请输入选项 [0-2]: " num
    case "${num}" in
    0)
        show_menu
        ;;
    1)
        ip_check
        ;;
    2)
        route_check
        ;;
    *)
        LOGE "请输入正确的数字选项 [0-2]!"
        ;;
    esac
}

# 【中文注释】：这是新添加的“服务器DNS检测”函数
dns_check() {
    echo ""
    
    # 【中文注释】：定义临时文件保存路径
    local script_file="/tmp/dnsjc.sh"
    
    # 【中文注释】：第一步：下载脚本
    # 使用 curl 下载，通过 tr 删除可能存在的 Windows 换行符(\r)，然后写入临时文件
    # 这样做可以确保 stdin（标准输入）不被占用，read 命令才能正常工作
    echo "正在下载检测脚本..."
    curl -Ls https://raw.githubusercontent.com/xeefei/X-Panel/master/dnsjc.sh | tr -d '\r' > "$script_file"
    
    # 【中文注释】：第二步：检查文件是否下载成功（文件存在且大小不为0）
    if [ -s "$script_file" ]; then
        # 【中文注释】：第三步：赋予脚本执行权限
        chmod +x "$script_file"
        
        # 【中文注释】：第四步：直接执行脚本
        # 此时脚本接管前台，你可以正常输入国家名称
        "$script_file"
        
        # 【中文注释】：第五步：执行完毕后删除临时文件，保持系统整洁
        rm -f "$script_file"
    else
        echo "错误：脚本下载失败，请检查网络连接。"
    fi
    
    # 【中文注释】：检查是否是作为非交互式命令调用的
    # 如果 $# (参数个数) 为 0，说明是从菜单调用的，执行完后返回主菜单
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
    # 【中文注释】：如果参数个数不为 0 (例如 '0')，说明是命令行调用的，函数结束
}

# =========================================================
# 【新功能】: 系统内核深度调优 (集成 TCP/BBR/内存优化)
# =========================================================

# 调优主菜单 (交互入口)
system_tuning_menu() {
    echo -e "
  ${green}系统内核深度调优 (基于内存智能计算)${plain}

  ${yellow}包含 BBR+FQ, TCP Fast Open, 缓冲区及队列优化${plain}
  ——————————————————————
  ${green}1.${plain} 智能分析硬件并应用优化 (推荐)
  
  ${green}2.${plain} “还原/卸载” 所有优化
  
  ${green}0.${plain} 返回主菜单
  "
    echo && read -p "请输入选项 [0-2]: " num
    case "${num}" in
    0) show_menu ;;
    1) optimize_system ;;
    2) revert_optimization ;;
    *) LOGE "请输入正确的数字 [0-2]"; system_tuning_menu ;;
    esac
}

# 计算并应用优化配置
optimize_system() {
    local sysctl_conf="/etc/sysctl.d/xpanel-optimized.conf"

    # ============================================
    # 【新增】: 自动检测当前 BBR 状态
    # ============================================
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

    echo ""
    LOGI "正在进行环境预检..."
    sleep 1
    if [[ "$current_cc" == "bbr" && "$current_qdisc" == "fq" ]]; then
        echo -e "  - 当前状态: ${green}已开启 BBR + FQ${plain}"
        echo -e "  - 操作目标: ${yellow}将基于当前环境执行【深度参数调优/升级】${plain}"
    else
        echo -e "  - 当前状态: ${red}未完全开启 BBR (当前: ${current_cc:-未知})${plain}"
        echo -e "  - 操作目标: ${green}准备进行【全新安装与优化】${plain}"
    fi
    echo ""

    # 1. 硬件检测
    local total_mem=$(free -m | awk '/^Mem:/{print $2}' | tr -d '\r')
    local cpu_cores=$(nproc)
    
    LOGI "正在检测系统硬件状态..."
    sleep 1
    echo -e "  - 物理内存: ${green}${total_mem} MB${plain}"
    echo -e "  - CPU 核心:  ${green}${cpu_cores} 核${plain}"
    echo ""

    # 2. 动态参数计算 (基于内存分级算法)
    local rmem_max wmem_max somaxconn tier
    
    if [ "$total_mem" -le 512 ]; then
        tier="入门级 (Entry)"
        rmem_max=$((8 * 1024 * 1024))
        wmem_max=$((8 * 1024 * 1024))
        somaxconn="4096"
    elif [ "$total_mem" -le 1024 ]; then
        tier="轻量级 (Light)"
        rmem_max=$((16 * 1024 * 1024))
        wmem_max=$((16 * 1024 * 1024))
        somaxconn="16384"
    elif [ "$total_mem" -le 4096 ]; then
        tier="标准级 (Standard)"
        rmem_max=$((32 * 1024 * 1024))
        wmem_max=$((32 * 1024 * 1024))
        somaxconn="32768"
    elif [ "$total_mem" -le 8192 ]; then
        tier="高性能级 (HighPerf)"
        rmem_max=$((64 * 1024 * 1024))
        wmem_max=$((64 * 1024 * 1024))
        somaxconn="65535"
    # 【修改】else 变成了大于 8GB 的旗舰配置
    else
        tier="旗舰级 (Flagship)"
        # 给 16G+ 内存机器分配 128MB 缓冲区（适合 10Gbps+ 专线）
        rmem_max=$((128 * 1024 * 1024))
        wmem_max=$((128 * 1024 * 1024))
        somaxconn="65535"
    fi
    
    LOGI "匹配优化等级: ${yellow}${tier}${plain}"

    # 计算 TCP 缓冲区 (Min Default Max)
    local rmem_default=$((rmem_max / 4))
    local wmem_default=$((wmem_max / 4))
    local tcp_rmem="4096 $rmem_default $rmem_max"
    local tcp_wmem="4096 $wmem_default $wmem_max"

    # 3. 备份旧配置 (如果存在)
    sleep 1
    if [ -f "$sysctl_conf" ]; then
        cp "$sysctl_conf" "${sysctl_conf}.bak"
        LOGI "检测到旧的优化配置文件，已自动备份。"
    fi
    
    # 确保目录存在
    mkdir -p /etc/sysctl.d

    # 4. 写入新配置 (融合最佳实践)
    cat > "$sysctl_conf" << EOF
# ==============================================================================
# X-Panel-Pro Linux Network Optimization
# Optimization Tier: ${tier} | Memory: ${total_mem}MB
# Generated by X-Panel-Pro Script
# ==============================================================================

# --- 核心 BBR 拥塞控制 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TCP 缓冲区优化 (动态计算) ---
net.core.rmem_max = ${rmem_max}
net.core.wmem_max = ${wmem_max}
net.ipv4.tcp_rmem = ${tcp_rmem}
net.ipv4.tcp_wmem = ${tcp_wmem}

# --- 连接队列优化 ---
net.core.somaxconn = ${somaxconn}
net.core.netdev_max_backlog = ${somaxconn}
net.ipv4.tcp_max_syn_backlog = ${somaxconn}

# --- TCP 连接行为优化 ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_window_scaling = 1

# --- Time-Wait 状态优化 ---
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144

# --- Keepalive 优化 (防止 SSH/代理断连) ---
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 6

# --- 高级特性 ---
# TCP Fast Open (减少握手延迟, 3 = 开启客户端和服务器端)
net.ipv4.tcp_fastopen = 3
# MTU 探测 (解决部分网络环境下的黑洞问题)
net.ipv4.tcp_mtu_probing = 1

# --- 系统通用资源限制 ---
fs.file-max = 2097152
vm.swappiness = 10
EOF
    sleep 1
    echo ""
    LOGI "配置文件写入成功: ${sysctl_conf}"

    # 5. 应用配置
    sleep 2
    # 使用 -p 指定文件加载，会立即覆盖掉系统中可能存在的旧参数
    if sysctl -p "$sysctl_conf" >/dev/null 2>&1; then
        LOGI "-------->>>>〔所有系统内核参数〕加载成功！"
    else
        # 尝试 system 全量加载作为后备
        sysctl --system >/dev/null 2>&1
        LOGI "使用 sysctl --system 强制加载完成。"
    fi

    # 6. 验证 BBR
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    local qdisc=$(sysctl -n net.core.default_qdisc)
    sleep 2
    
    echo ""
    echo -e "------------- 验证结果 -------------"
    if [[ "$cc" == "bbr" && "$qdisc" == "fq" ]]; then
        echo -e "拥塞控制算法: ${green}${cc}${plain}"
        echo -e "队列调度策略: ${green}${qdisc}${plain}"
        echo -e "${green}恭喜！系统内核深度优化已成功生效！${plain}"
    else
        echo -e "拥塞控制算法: ${red}${cc}${plain}"
        LOGE "警告：BBR 未能正确开启，请检查您的系统内核是否支持 (需 4.9+)。"
    fi
    
    echo ""
    read -p "按回车键返回......" temp
    system_tuning_menu
}

# 还原优化
revert_optimization() {
    local sysctl_conf="/etc/sysctl.d/xpanel-optimized.conf"

    confirm "确定要移除所有优化配置并恢复默认吗？" "n"
    if [[ $? != 0 ]]; then
        system_tuning_menu
    fi

    if [ -f "$sysctl_conf" ]; then
        rm -f "$sysctl_conf"
        LOGI "已删除优化配置文件: $sysctl_conf"
    else
        LOGE "未找到优化配置文件，可能尚未安装。"
    fi
    
    LOGI "正在重载系统默认设置..."
    sysctl --system >/dev/null 2>&1
    
    echo -e "${green}系统已恢复默认配置。建议重启服务器以彻底清理缓存。${plain}"
    echo ""
    read -p "按回车键返回......" temp
    system_tuning_menu
}

# =========================================================
# [新增功能] 远程备份与急救还原 (SSH版 - 增强兼容版)
# 逻辑与 Web Go 端保持一致，用于面板崩溃时的紧急救援
# =========================================================

# 30-0. 智能依赖检查与安装 (兼容 Debian/Ubuntu/CentOS/Alpine)
check_zip_tools() {
    # 1. 检查工具是否已存在
    echo ""
    if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
        LOGI "环境检查：zip/unzip 工具已安装。"
        return 0
    fi
    
    LOGI "检测到系统缺少 zip 或 unzip 组件，正在尝试自动安装......"
    sleep 2
    
    # 2. 根据脚本开头获取的 release 变量选择安装方式
    # (如果脚本开头未定义 release，尝试手动获取)
    if [[ -z "$release" ]]; then
        if [[ -f /etc/os-release ]]; then source /etc/os-release; release=$ID; fi
    fi

    case "${release}" in
        centos|almalinux|rocky|oracle|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y zip unzip
            else
                yum install -y zip unzip
            fi
            ;;
        ubuntu|debian|armbian|kali)
            # -qq 减少输出，但保留错误信息
            apt-get update >/dev/null 2>&1
            apt-get install -y zip unzip
            ;;
        alpine)
            apk add --no-cache zip unzip
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm zip unzip
            ;;
        *)
            # 兜底策略：如果识别不出系统，尝试常见命令
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y zip unzip
            elif command -v yum >/dev/null 2>&1; then
                yum install -y zip unzip
            else
                LOGE "无法自动安装 zip 工具，请您手动执行安装命令后重试。"
                return 1
            fi
            ;;
    esac

    # 3. 二次检查
    if command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
        LOGI "zip/unzip 工具安装成功！"
        echo ""
        sleep 2
    else
        LOGE "安装失败，请检查网络或手动安装 zip 和 unzip。"
        return 1
    fi
}

# 30-1. 远程备份功能
remote_backup() {
    # 运行前先检查 zip 工具
    check_zip_tools || return 1
    echo ""
    sleep 1
    
    # 定义关键路径和变量
    local LICENSE_FILE="/usr/local/x-ui/bin/license.key"
    local DB_FILE="/etc/x-ui/x-ui.db"
    local CONFIG_FILE="/usr/local/x-ui/bin/config.json"
    # PHP 接口地址
    local API_URL="https://auth.x-panel.vip/backup_api.php"
    
    echo -e "${yellow}正在执行“远程备份操作”......${plain}"
    sleep 2
    echo ""

    # 1. 检查授权文件
    if [[ ! -f "$LICENSE_FILE" ]]; then
        LOGE "错误：未找到“授权文件”，无法验证身份，备份终止。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi
    local LICENSE_KEY=$(cat "$LICENSE_FILE" | tr -d '\n\r')

    # 检查数据库文件
    if [[ ! -f "$DB_FILE" ]]; then
        LOGE "错误：未找到数据库文件 (x-ui.db)，面板可能已损坏，备份终止。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    # 检查配置文件 config.json 
    if [[ ! -f "$CONFIG_FILE" ]]; then
        LOGE "错误：未找到配置文件 (config.json)，数据不完整，备份终止。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    # 2. 动态获取本机 IP (用于 PHP 端校验)
    # [优化逻辑] 优先 IPv4，失败则尝试 IPv6 (与 Go 端逻辑完全同步)
    
    # 尝试 1: IPv4 优先 (curl -4)
    local SERVER_IP=$(curl -s4m5 https://api.ip.sb/ip -k)
    
    if [[ -z "$SERVER_IP" ]]; then
        # 尝试 2: 如果 api.ip.sb 的 IPv4 失败，试 ifconfig.me 的 IPv4
        SERVER_IP=$(curl -s4m5 https://ifconfig.me/ip -k)
    fi

    # 尝试 3: [新增] 如果上述 IPv4 都获取不到，说明可能是纯 IPv6 机器
    # 此时尝试强制使用 IPv6 (curl -6)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s6m5 https://api.ip.sb/ip -k)
    fi

    # 尝试 4: 兜底 (不带参数，自动协商)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s -m 5 https://api.ipify.org -k)
    fi
    
    sleep 2
    LOGI "授权身份验证中... (License: ...${LICENSE_KEY: -6} / IP: $SERVER_IP)"
    echo ""

    # 3. 准备临时目录打包
    local TMP_DIR="/tmp/xui_backup_tmp_$(date +%s)"
    local TMP_ZIP="/tmp/xui_backup_$(date +%s).zip"
    
    mkdir -p "$TMP_DIR"
    
    # 4. 复制两个文件
    cp "$DB_FILE" "$TMP_DIR/x-ui.db"
    cp "$CONFIG_FILE" "$TMP_DIR/config.json"

    # 进入目录打包，确保压缩包内不含路径前缀 (和 Go 端逻辑一致)
    # [修改点] 使用 -j 参数强制忽略路径，确保 ZIP 根目录就是 db 和 json
    cd "$TMP_DIR"
    zip -q -j "$TMP_ZIP" "./x-ui.db" "./config.json"
    if [[ $? -ne 0 ]]; then
        LOGE "文件打包失败！请检查磁盘空间或文件权限。"
        rm -rf "$TMP_DIR" "$TMP_ZIP"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    # 5. 转 Base64 编码
    local DATA_BASE64=$(base64 -w 0 "$TMP_ZIP")

    sleep 1
    # 6. 上传至 PHP 接口
    LOGI "正在加密上传“备份数据”至云端......"
    RESPONSE=$(curl -s -X POST "$API_URL" \
        -d "action=backup" \
        -d "key=$LICENSE_KEY" \
        -d "ip=$SERVER_IP" \
        --data-urlencode "data=$DATA_BASE64")

    # 7. 清理临时文件
    cd ~
    rm -rf "$TMP_DIR" "$TMP_ZIP"

    # 8. 解析结果并提示
    if echo "$RESPONSE" | grep -q '"success":true'; then
        echo ""
        sleep 2
        echo -e "${green}✅ ------>>>> 备份成功！！！${plain}"
        echo ""
        sleep 1
        echo -e "${green}您的 x-ui.db 和 config.json 已成功同步至云端。${plain}"
        echo ""
    else
        echo ""
        echo -e "${red}❌ [备份失败]${plain}"
        echo -e "服务器返回错误信息: $RESPONSE"
        echo ""
    fi

    # [修改点] 判断是菜单调用还是命令行调用
    if [[ $# > 0 ]]; then
        return 0
    else
        before_show_menu
    fi
}

# 30-2. 急救还原功能
rescue_restore() {
    # 运行前先检查环境组件
    check_zip_tools || return 1
    echo ""

    # 定义关键路径和变量
    local LICENSE_FILE="/usr/local/x-ui/bin/license.key"
    local API_URL="https://auth.x-panel.vip/backup_api.php"
    local DB_PATH="/etc/x-ui/x-ui.db"
    local CONFIG_PATH="/usr/local/x-ui/bin/config.json"

    echo -e "${yellow}====== ⚠️ 急救还原模式 ⚠️ ======${plain}"
    echo ""
    echo -e "1、此操作将从云端拉取“该机器”对应的最新备份。"
    echo ""
    echo -e "2、并且会${red}〔强制覆盖〕${plain}您当前的“面板数据库配置”。"
    echo ""
    echo -e "3、还原结束时面板将“自动重启”，以应用〔配置更改〕。"
    echo ""
    echo -e "4、作用：当在面板无法打开/访问时，即可使用此功能挽救。"
    echo ""
    
    # 如果是带参数运行，默认视为已确认，不弹交互确认
    if [[ $# -eq 0 ]]; then
        confirm "您确定要继续吗?" "n"
        if [[ $? != 0 ]]; then
            before_show_menu
            return 0
        fi
    fi

    # 1. 验证必要文件
    if [[ ! -f "$LICENSE_FILE" ]]; then
        LOGE "未找到“授权文件”，无法验证身份。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi
    local LICENSE_KEY=$(cat "$LICENSE_FILE" | tr -d '\n\r')

    # 2. 获取 IP (必须与备份时的 IP 一致)
    local SERVER_IP=$(curl -s4m8 http://ip.sb -k)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s6m8 http://ip.sb -k)
    fi
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(curl -s https://api.ipify.org)
    fi

    echo ""
    sleep 2
    LOGI "正在连接云端“拉取备份数据”...... (IP: $SERVER_IP)"

    # 3. 发起请求
    RESPONSE=$(curl -s -X POST "$API_URL" \
        -d "action=restore" \
        -d "key=$LICENSE_KEY" \
        -d "ip=$SERVER_IP")

    # 4. 验证响应
    if ! echo "$RESPONSE" | grep -q '"success":true'; then
        LOGE "云端请求失败，未找到该机器的备份记录。"
        echo -e "详细信息: $RESPONSE"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    # 5. 提取 Base64 数据
    # 使用 sed 精确提取 JSON 中的 data 字段
    echo ""
    LOGI "备份数据下载成功，正在解析......"
    sleep 1

    # [优化] 使用更严谨的提取方式，去掉可能存在的干扰字符
    local REMOTE_DATA=$(echo "$RESPONSE" | sed 's/\\//g' | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')

    if [[ -z "$REMOTE_DATA" ]]; then
        LOGE "解析失败：云端返回的数据为空。"
        [[ $# -eq 0 ]] && before_show_menu
        return 1
    fi

    # 6. 解码与解压
    local TMP_RESTORE_ZIP="/tmp/xui_restore_$(date +%s).zip"
    local TMP_RESTORE_DIR="/tmp/xui_restore_dir_$(date +%s)"
    mkdir -p "$TMP_RESTORE_DIR"

    # Base64 解码
    echo "$REMOTE_DATA" | base64 -d > "$TMP_RESTORE_ZIP"

    # 检查文件完整性
    if [[ ! -s "$TMP_RESTORE_ZIP" ]]; then
        LOGE "文件解码错误，文件大小为 0。"
        rm -rf "$TMP_RESTORE_ZIP" "$TMP_RESTORE_DIR"
        return 1
    fi

    # 解压
    unzip -o -q "$TMP_RESTORE_ZIP" -d "$TMP_RESTORE_DIR"
    
    if [[ $? -ne 0 ]]; then
        # 兼容逻辑：如果不是 ZIP，尝试作为纯 DB 恢复
        LOGI "ZIP 解压失败，尝试兼容模式还原数据库..."
        cp -f "$TMP_RESTORE_ZIP" "$DB_PATH"
        if [[ $? -eq 0 ]]; then
            LOGI "✅ “数据库文件”已恢复"
        else
            LOGE "❌ 恢复失败：无法识别备份文件格式。"
            rm -rf "$TMP_RESTORE_ZIP" "$TMP_RESTORE_DIR"
            return 1
        fi
    else
        echo ""
        sleep 2
        # 7. 严格还原逻辑：必须两个文件都存在
        LOGI "正在校验备份完整性......"
        echo ""
        
        if [[ ! -f "$TMP_RESTORE_DIR/x-ui.db" ]] || [[ ! -f "$TMP_RESTORE_DIR/config.json" ]]; then
            LOGE "还原失败：云端备份包数据不完整（缺少 db 或 json），为了安全已终止还原。"
            rm -rf "$TMP_RESTORE_ZIP" "$TMP_RESTORE_DIR"
            [[ $# -eq 0 ]] && before_show_menu
            return 1
        fi

        # 校验通过，开始执行物理覆盖
        LOGI "校验通过，正在覆盖本机文件......"
        echo ""
        sleep 2
        
        cp -f "$TMP_RESTORE_DIR/x-ui.db" "$DB_PATH"
        echo -e " ------>>> 数据库 (x-ui.db) 已覆盖"
        echo ""

        sleep 1
        cp -f "$TMP_RESTORE_DIR/config.json" "$CONFIG_PATH"
        echo -e " ------>>> 配置文件 (config.json) 已覆盖"
        echo ""

        LOGI "✅ 所有“核心文件”已还原。"
        echo ""
    fi

    # 8. 清理并重启
    rm -rf "$TMP_RESTORE_ZIP" "$TMP_RESTORE_DIR"

    echo ""
    sleep 1
    echo -e "${green}✅ ------>>>> 还原成功！！！${plain}"
    echo ""
    echo -e "“面板配置”已恢复到最新备份状态。"
    echo ""
    sleep 1
    echo -e "${yellow}正在“重启面板”以应用更改，请稍候......${plain}"
    echo ""
    sleep 2
    
    # 强制重启
    restart 0
}

# =========================================================
# [新增功能 【第31项】] 数据库一键迁移 (跨 VPS 迁移)
# 同时打包传输 x-ui.db 和 config.json，并自动替换 IP/域名
# =========================================================
migrate_database() {
    check_zip_tools || return 1
    echo ""
    echo -e "${yellow}==================================================${PLAIN}"
    echo -e "${yellow}       X-Panel-Pro 跨服务器“面板数据库”一键迁移工具       ${PLAIN}"
    echo -e "${yellow}==================================================${PLAIN}"
    echo -e "${green}提示：请在【新 VPS】上运行此选项，它将自动拉取旧 VPS 的数据库与配置文件。${plain}\n"

    read -rp "请输入旧 VPS 的 IP 地址: " OLD_IP
    [[ -z "$OLD_IP" ]] && LOGE "旧 IP 不能为空！" && before_show_menu && return 1
    sleep 1
    echo ""

    read -rp "请输入旧 VPS 的 SSH 端口 (默认 22): " OLD_PORT
    OLD_PORT=${OLD_PORT:-22}
    echo ""
    sleep 1

    read -rp "请输入旧 VPS 的 root 密码: " OLD_PASSWORD
    [[ -z "$OLD_PASSWORD" ]] && LOGE "密码不能为空！" && before_show_menu && return 1
    sleep 1
    echo ""

    # 获取当前新 VPS 的 IP
    local NEW_IP=$(curl -s4m5 http://ip.sb -k)
    [[ -z "$NEW_IP" ]] && NEW_IP=$(curl -s6m5 http://ip.sb -k)
    [[ -z "$NEW_IP" ]] && NEW_IP=$(curl -s https://api.ipify.org)
    echo -e "${green}---->> 检测到当前新 VPS 的 IP 为: ${NEW_IP}${plain}"
    sleep 2
    echo ""

    # 检查并安装 sshpass
    if ! command -v sshpass &> /dev/null; then
        echo -e "${yellow}正在安装必要依赖 (sshpass)...${plain}"
        echo ""
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y sshpass
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y epel-release && yum install -y sshpass
        fi
    fi
    sleep 1
    echo ""

    echo -e "\n${yellow}[1/5] 正在连接旧 VPS 并打包数据库与配置文件......${plain}"
    echo ""
    sshpass -p "$OLD_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$OLD_PORT" root@"$OLD_IP" << 'EOF'
    if [ -d "/etc/x-ui" ] && [ -f "/etc/x-ui/x-ui.db" ]; then
        cd /tmp
        rm -rf xpanel_migration_pkg.zip
        # 同时打包 x-ui.db 和 config.json
        if [ -f "/usr/local/x-ui/bin/config.json" ]; then
            zip -q -j xpanel_migration_pkg.zip /etc/x-ui/x-ui.db /usr/local/x-ui/bin/config.json
        else
            zip -q -j xpanel_migration_pkg.zip /etc/x-ui/x-ui.db
        fi
        echo "PACK_SUCCESS"
    else
        echo "DIR_NOT_FOUND"
    fi
EOF

    if [ $? -ne 0 ]; then
        LOGE "错误：连接旧 VPS 失败，请检查 IP、端口或 “root密码” 是否正确?"
        before_show_menu
        return 1
    fi

    sleep 2
    echo ""
    echo ""
    echo -e "${yellow}[2/5] 正在将“迁移数据包”下载到新 VPS......${plain}"
    sshpass -p "$OLD_PASSWORD" scp -o StrictHostKeyChecking=no -P "$OLD_PORT" root@"$OLD_IP":/tmp/xpanel_migration_pkg.zip /tmp/xpanel_migration_pkg.zip

    echo ""
    if [ ! -f "/tmp/xpanel_migration_pkg.zip" ]; then
        LOGE "错误：迁移包下载失败！"
        before_show_menu
        return 1
    fi
    echo -e "${green}-------->>> “迁移数据包”下载成功！${plain}"
    sleep 2

    echo ""
    echo -e "${yellow}[3/5] 正在新 VPS 上停止“面板服务”......${plain}"
    systemctl stop x-ui 2>/dev/null

    mkdir -p /etc/x-ui
    mkdir -p /usr/local/x-ui/bin
    sleep 2

    echo ""
    echo -e "${yellow}[4/5] 正在解压并恢复数据库与配置文件......${plain}"
    mkdir -p /tmp/xpanel_extracted
    unzip -o -q /tmp/xpanel_migration_pkg.zip -d /tmp/xpanel_extracted/

    sleep 1
    echo ""
    if [ -f "/tmp/xpanel_extracted/x-ui.db" ]; then
        cp -f /tmp/xpanel_extracted/x-ui.db /etc/x-ui/x-ui.db
        echo -e "${green} -------->>> 数据库 (x-ui.db) 恢复成功${plain}"
    fi
    sleep 1
    echo ""
    if [ -f "/tmp/xpanel_extracted/config.json" ]; then
        cp -f /tmp/xpanel_extracted/config.json /usr/local/x-ui/bin/config.json
        echo -e "${green} -------->>> 配置文件 (config.json) 恢复成功${plain}"
    fi

    sleep 2
    echo ""
    # 5. 自动批量替换数据库中的旧 IP/域名 为 新 IP/域名
    echo -e "${yellow}[5/5] 智能修正数据库中的旧 IP/域名节点信息......${plain}"
    
    echo ""
    # 【第一步】：先问用户旧机器用的是什么（作为查找条件）
    read -rp "请输入旧 VPS 之前绑定的【旧 IP 或旧域名】(若无需替换请直接回车跳过): " OLD_HOST
    sleep 1
    echo ""

    if [ -n "$OLD_HOST" ]; then
        # 获取当前新 VPS 的默认 IP 作为参考
        local DEFAULT_NEW_IP=$(curl -s4m5 http://ip.sb -k)
        [[ -z "$DEFAULT_NEW_IP" ]] && DEFAULT_NEW_IP=$(curl -s6m5 http://ip.sb -k)
        [[ -z "$DEFAULT_NEW_IP" ]] && DEFAULT_NEW_IP=$(curl -s https://api.ipify.org)
        
        echo -e "${green}--->> 检测到当前新 VPS 的默认 IP 为: ${DEFAULT_NEW_IP}${plain}"
    sleep 2
    echo ""
        
        # 【第二步】：再问用户新机器要生效的是什么（作为替换目标，默认是新机器IP，也可以手动输新域名）
        read -rp "请输入迁移后需要生效的【新 IP 或新域名】(直接回车默认使用新 IP: $DEFAULT_NEW_IP): " NEW_HOST
        NEW_HOST=${NEW_HOST:-$DEFAULT_NEW_IP}
    sleep 1

        # 执行数据库批量替换（修复了原先 address 列不存在导致的报错）
        if [ -f "/etc/x-ui/x-ui.db" ]; then
            if ! command -v sqlite3 &> /dev/null; then
                apt-get install -y sqlite3 2>/dev/null || yum install -y sqlite3 2>/dev/null
            fi
            
            # 使用 SQLite 的 replace 函数安全更新全局配置表和底层入站流设置
            sqlite3 /etc/x-ui/x-ui.db "UPDATE settings SET value = replace(value, '$OLD_HOST', '$NEW_HOST') WHERE value LIKE '%$OLD_HOST%';"
            sqlite3 /etc/x-ui/x-ui.db "UPDATE inbounds SET stream_settings = replace(stream_settings, '$OLD_HOST', '$NEW_HOST');"
            sqlite3 /etc/x-ui/x-ui.db "UPDATE inbounds SET settings = replace(settings, '$OLD_HOST', '$NEW_HOST');"
            
            # 同步更新 config.json 中的对应字符
            if [ -f "/usr/local/x-ui/bin/config.json" ]; then
                sed -i "s/$OLD_HOST/$NEW_HOST/g" /usr/local/x-ui/bin/config.json
            fi

            sleep 2
            echo ""
            echo -e "${green}---->>> 数据库 “IP/域名” 批量替换完成：${OLD_HOST} ➔ ${NEW_HOST}${plain}"
        fi
    else
        sleep 1
        echo ""
        echo -e "${yellow}------>>>> 已跳过数据库 “IP/域名”自动替换。${plain}"
    fi

    sleep 1
    # 清理临时文件
    rm -f /tmp/xpanel_migration_pkg.zip
    rm -rf /tmp/xpanel_extracted
    sshpass -p "$OLD_PASSWORD" ssh -o StrictHostKeyChecking=no -p "$OLD_PORT" root@"$OLD_IP" "rm -f /tmp/xpanel_migration_pkg.zip"

    sleep 2
    echo ""
    echo ""
    echo -e "\n${green}==================================================${PLAIN}"
    echo -e "${green}恭喜！X-Panel-Pro “数据库与配置”一键迁移成功！${plain}"
    echo ""
    echo -e "${green}--------->>>>>>>当前面板运行的新 IP: ${NEW_IP}${plain}"
    echo -e "${green}==================================================${PLAIN}"

    # 强制重启
    restart 0
}

# =========================================================
# 【新功能 【第32项】】 Cloudflare Argo 隧道 (防失联管理)
# =========================================================

install_cloudflared() {
    if command -v cloudflared &>/dev/null; then
        LOGI "cloudflared 已经安装。"
        return 0
    fi
    sleep 1
    
    LOGI "正在检测系统架构并安装 cloudflared......."
    echo ""
    local arch=$(uname -m)
    local dl_url=""
    
    if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
        dl_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
        dl_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    else
        LOGE "不支持的系统架构: $arch"
        return 1
    fi
    
    curl -L --output /usr/local/bin/cloudflared "$dl_url"
    chmod +x /usr/local/bin/cloudflared
    sleep 2
    echo ""
    
    if command -v cloudflared &>/dev/null; then
        LOGI "cloudflared 安装成功！"
        return 0
    else
        LOGE "cloudflared 安装失败，请检查网络连接。"
        return 1
    fi
}

argo_tunnel_menu() {
    echo -e "
————————————————————————————————————————————————
  ${yellow}Cloudflare Argo 隧道 (防失联管理)${plain}
————————————————————————————————————————————————
  ${green}1.${plain} 配置并启动固定 Argo 隧道 (Token 模式 - 防失联推荐)
  ${green}2.${plain} 生成临时应急隧道 (Quick Tunnel - 临时测试用)
  ${green}3.${plain} 查看 Argo 隧道运行状态
  ${green}4.${plain} 卸载/停止 Argo 隧道服务
————————————————————————————————————————————————
  ${green}0.${plain} 返回主菜单
"
    read -p "请输入选项 [0-4]: " choice
    case "${choice}" in
    0)
        show_menu
        ;;
    1)
        setup_permanent_argo
        ;;
    2)
        start_quick_argo
        ;;
    3)
        check_argo_status
        ;;
    4)
        uninstall_argo
        ;;
    *)
        LOGE "无效选项，请输入数字 [0-4]"
        argo_tunnel_menu
        ;;
    esac
}

setup_permanent_argo() {
    echo ""
    echo -e "${yellow}=== 配置固定 Argo 隧道 (防失联核心) ===${plain}"
    echo ""
    echo -e "使用说明："
    echo -e "1. 登录 Cloudflare Zero Trust 后台 (one.dash.cloudflare.com)，"
    echo -e "2. 进入 Networks（联网） -> Tunnels -> 创建一个新 Tunnel，"
    echo -e "3. 复制生成的 ${green}Tunnel Token${plain} (一段很长的字符串)，"
    echo -e "4. Token 获取 ${green}以“ey”开头${plain} (在 CF 后台是****隐藏起来的)，"
    echo -e "5. 在下方粘贴完整的 Token，即可将本服务器与 Cloudflare 边缘网络映射绑定。\n"
    echo ""

    read -rp "请在此粘贴您的 Cloudflare Tunnel Token: " CF_TOKEN
    [[ -z "$CF_TOKEN" ]] && LOGE "Token 不能为空！" && before_show_menu && return 1

    # 确保安装了 cloudflared
    install_cloudflared || return 1
    echo ""
    sleep 2

    echo -e "${yellow}正在将 cloudflared 注册为系统服务并启动......${plain}"
    echo ""
    
    # 如果之前有旧服务，先卸载清理
    cloudflared service uninstall >/dev/null 2>&1

    # 安装为系统服务
    cloudflared service install "$CF_TOKEN"
    echo ""
    
    sleep 2
    if [ $? -eq 0 ]; then
        echo -e "\n${green}✅ Argo 隧道安装并启动成功！${plain}"
        echo ""
        echo -e "${green}提示：您现在可以在 Cloudflare Zero Trust 后台为该隧道绑定一个自定义域名（例如 panel.yourdomain.com），${plain}"
        echo ""
        echo -e "${green}并配置 Public Hostname（路由） 指向本地面板端口（例如 https://localhost:15208）。${plain}"
        echo ""
        echo -e "${yellow}================================================================${plain}"
        echo -e "${green}👉 下一步：请前往 Cloudflare Zero Trust 后台完成域名绑定：${plain}"
        echo -e "1. 登录 ${yellow}one.dash.cloudflare.com${plain} -> Networks（联网） -> Tunnels"
        echo -e "2. 找到该隧道，点击 ${yellow}Configure（添加路由）${plain} -> ${yellow}已发布的应用程序${plain} -> 添加域名"
        echo -e "3. ${red}关键配置（核心防坑项）：${plain}"
        echo -e "   - 协议头选择: ${yellow}必须以“https”开头，必须保留：“localhost”字符串${plain}"
        echo -e "   - Service URL 填入:  ${yellow}https://localhost:面板端口${plain} (例如 https://localhost:15208)"
        echo -e "   - ${yellow}点击展开下方的 Additional application settings（其他应用程序设置）${plain}"
        echo -e "   - ${green}在“TLS”选项处必须“勾选/打开”--->禁用 TLS 证书验证${plain} (允许跳过自签证书校验)"
        echo -e "${yellow}================================================================${plain}"
        echo ""
        echo -e "${green}这样即使“服务器 IP 被封”，通过该域名依然能完美“访问后台面板”！${plain}"
        echo ""
        echo -e "${red}注意：在 CF 隧道后台绑定的“子域名”，不能去添加 A记录 解析到 VPS，CF自动解析！${plain}"
    else
        LOGE "Argo 隧道服务安装失败，请检查 Token 是否正确。"
    fi

    before_show_menu
}

start_quick_argo() {
    echo ""
    echo -e "${yellow}=== 生成临时应急隧道 (Quick Tunnel) ===${plain}"
    echo -e "提示：该功能会临时生成一个 *.trycloudflare.com 的随机外链，用于临时测试访问面板。"
    echo ""
    
    install_cloudflared || return 1
    
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -i 'port' | grep -Eo '[0-9]+' | tail -n 1)
    existing_port=${existing_port:-15208}

    # 【新增功能】：智能提取面板安全路径（Web Root / Base Path），并自动规范化格式
    local panel_path=$(/usr/local/x-ui/x-ui setting -show true 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -iE 'path|base' | awk '{print $NF}' | tr -d '"' | tr -d "'")
    if [ -z "$panel_path" ] || [ "$panel_path" = "-" ]; then
        panel_path="/"
    else
        [[ "$panel_path" != /* ]] && panel_path="/$panel_path"
        [[ "$panel_path" != */ ]] && panel_path="${panel_path}/"
    fi

    sleep 2

    echo ""
    echo -e "${green}正在为面板端口 (${existing_port}) 创建临时隧道，当前安全路径: [${panel_path}]，请稍候......${plain}"
    echo ""
    echo -e "${yellow}注意：下方将实时输出隧道地址，系统已为您自动拼接好带路径的完整直达链接。${yellow}"
    echo ""
    echo -e "${red}按 “Ctrl + C” 或“关闭 SSH终端”可以【销毁退出】临时隧道，不会留下任何联网痕迹。${plain}\n"

    # 【核心升级】：实时捕获 cloudflared 输出，一旦生成随机域名，立即自动拼接并高亮打印完整带路径链接
    cloudflared tunnel --no-tls-verify --url https://127.0.0.1:"${existing_port}" 2>&1 | while IFS= read -r line; do
        echo "$line"
        if echo "$line" | grep -q "trycloudflare.com"; then
            local raw_url=$(echo "$line" | grep -Eo 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com')
            if [ -n "$raw_url" ]; then
                local full_url="${raw_url}${panel_path}"
                echo -e "\n${green}================================================================${plain}"
                echo -e "${green}🔥 【一键直达面板完整链接 (复制到浏览器打开)】: ${yellow}${full_url}${plain}"
                echo -e "${green}================================================================${plain}\n"
            fi
        fi
    done
    
    before_show_menu
}

check_argo_status() {
    echo ""
    echo -e "${yellow}=== Argo 隧道运行状态 ===${plain}"
    if systemctl is-active --quiet cloudflared; then
        echo -e "服务状态: ${green}运行中 (Running)${plain}"
        echo ""
        systemctl status cloudflared --no-pager -l
    else
        echo -e "服务状态: ${red}未运行或未安装${plain}"
    fi
    before_show_menu
}

uninstall_argo() {
    confirm "您确定要卸载并停止 Argo 隧道服务吗？" "n"
    if [[ $? -eq 0 ]]; then
        systemctl stop cloudflared >/dev/null 2>&1
        cloudflared service uninstall >/dev/null 2>&1
        rm -f /usr/local/bin/cloudflared
        echo ""
        sleep 2
        echo -e "${green}Argo 隧道已成功卸载。${plain}"
    fi
    before_show_menu
}

# 30. 子菜单入口
backup_restore_menu() {
    echo -e "————————————————————————————————————————————————"
    echo -e "${yellow} 远程备份与急救还原 ${plain}"
    echo -e "————————————————————————————————————————————————"
    echo -e "说明：当面板无法访问时，使用此功能与云端同步数据"
    echo -e "————————————————————————————————————————————————"
    echo -e "${green}  1.${plain} 远程备份 (备份当前配置 -> 云端)"
    echo -e "${green}  2.${plain} 急救还原 (云端拉取 -> 覆盖本机)"
    echo -e "————————————————————————————————————————————————"
    echo -e "${green}  0.${plain} 返回主菜单"
    echo -e ""
    read -p "请输入选项 [0-2]: " choice
    case "$choice" in
        1) remote_backup ;;
        2) rescue_restore ;;
        0) show_menu ;;
        *) echo -e "${red}无效选项${plain}"; backup_restore_menu ;;
    esac
}

# =========================================================
# 【新增功能 【第33选项】】 创建 IPv6 链接（应急防封）
# =========================================================
get_random_port() {
    local port
    while true; do
        port=$((RANDOM % 45536 + 20000))
        if ! ss -tuln 2>/dev/null | grep -q ":$port " && ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "$port"
            break
        fi
    done
}

create_ipv6_links() {
    echo ""
    echo -e "${yellow}=== 创建 IPv6 链接（应急防封） ===${plain}"
    echo ""

    # 1. 自动检测并获取 VPS 的 IPv6 地址
    local v6=$(ip -6 addr show scope global 2>/dev/null | grep inet6 | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
    if [[ -z "$v6" ]]; then
        v6=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep ':' | grep -v '^fe80' | head -n 1)
    fi
    if [[ -z "$v6" ]]; then
        v6=$(curl -s6m8 http://ip.sb -k)
    fi
    if [[ -z "$v6" ]]; then
        v6=$(curl -s6m8 https://api.ip.sb/ip -k)
    fi
    if [[ -z "$v6" ]]; then
        v6=$(curl -s6m8 https://ipv6.icanhazip.com -k)
    fi

    if [[ -z "$v6" ]]; then
        LOGE "提示：此台 VPS 不支持创建 IPv6 链接（未检测到有效的 IPv6 地址）！"
        before_show_menu
        return 1
    fi

    LOGI "检测到服务器 IPv6 地址: [${v6}]"
    echo ""

    # 2. 子菜单让用户选择想要创建哪种类型的 Vless 链接
    echo -e "${green}请选择想要创建的 IPv6 代理链接类型：${plain}"
    echo -e "${green}1.${plain} 创建 Vless + TCP + Reality + Vision 链接"
    echo -e "${green}2.${plain} 创建 VLESS + XHTTP + Reality 链接"
    echo -e "${green}3.${plain} 同时创建“上述两种类型的链接”"
    echo -e "${green}0.${plain} 返回主菜单"
    echo ""
    read -rp "请输入选项 [0-3]: " v6_choice

    case "$v6_choice" in
        0)
            show_menu
            ;;
        1|2|3)
            # 确保安装了 sqlite3 工具以便将入站数据写入面板数据库
            if ! command -v sqlite3 &> /dev/null; then
                apt-get update >/dev/null 2>&1 && apt-get install -y sqlite3 >/dev/null 2>&1 || yum install -y sqlite3 >/dev/null 2>&1
            fi

            # 随机生成 UUID、20000以上未被占用的高位端口、随机 SNI 域名、默认 Short ID
            local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 32 | head -n 1 | sed -r 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')
            local port_vision=$(get_random_port)
            local port_xhttp=$(get_random_port)
            
            local domains=("sega.com" "tesla.com" "lovelive-anime.jp" "csuglobal.edu" "usc.edu")
            local sni=${domains[$RANDOM % ${#domains[@]}]}
            local sid="40"
            
            # 随机生成 XHTTP 的路径后缀（例如 8 位随机字符）
            local xhttp_rand_path=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | fold -w 8 | head -n 1)
            
            # 自动获取 Reality 密钥对 (私钥 priv 与 公钥 pbk)
            local xray_bin=$(find /usr/local/x-ui/bin/ -name "xray-linux-*" -type f | head -n 1)
            local priv=""
            local pbk=""
            if [ -x "$xray_bin" ]; then
                local x25519_out=$($xray_bin x25519 2>/dev/null)
                priv=$(echo "$x25519_out" | grep "PrivateKey" | awk '{print $2}')
                pbk=$(echo "$x25519_out" | grep "Password" | awk '{print $3}')
            fi
            if [ -z "$priv" ] || [ -z "$pbk" ]; then
                priv="gCkQ7TFpQVcESWkECewFAmYhjBFhzu3BgAGUp6Z0n1M"
                pbk="9jGTCeCm04ntbJ6BucbfAT2-Y0qU4jFL5lrvgjkLrhY"
            fi

            local sniffing_json='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

            sleep 2
            echo ""
            echo -e "${yellow}================================================================${plain}"
            echo -e "${green}“IPv6 防封代理链接”------->>>> 已经【成功生成】！${plain}"
            echo -e "${yellow}================================================================${plain}"
            echo ""

            sleep 2
            # 创建类型 1: Vless + TCP + Reality + Vision
            if [[ "$v6_choice" == "1" || "$v6_choice" == "3" ]]; then
                local p_v="$port_vision"
                local remark_v="IPv6-Vision-$p_v"
                local tag_v="v6-vision-$p_v"
                local settings_v="{\"clients\":[{\"id\":\"$uuid\",\"flow\":\"xtls-rprx-vision\",\"email\":\"$remark_v\",\"level\":0,\"enable\":true}],\"decryption\":\"none\",\"fallbacks\":[]}"
                local stream_v="{\"network\":\"tcp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"target\":\"${sni}:443\",\"xver\":0,\"serverNames\":[\"$sni\",\"www.$sni\"],\"settings\":{\"publicKey\":\"$pbk\",\"spiderX\":\"/\",\"mldsa65Verify\":\"\"},\"privateKey\":\"$priv\",\"maxClientVer\":\"\",\"minClientVer\":\"\",\"maxTimediff\":0,\"mldsa65Seed\":\"\",\"shortIds\":[\"$sid\"]},\"tcpSettings\":{\"acceptProxyProtocol\":false,\"header\":{\"type\":\"none\"}}}"
                
                # 写入面板数据库，打通后台入站数据
                if [ -f "/etc/x-ui/x-ui.db" ]; then
                    sqlite3 /etc/x-ui/x-ui.db "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, '$remark_v', 1, 0, '::', $p_v, 'vless', '$settings_v', '$stream_v', '$tag_v', '$sniffing_json');"
                fi

                local link_vision="vless://${uuid}@[${v6}]:${p_v}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&spx=%2F&type=tcp&headerType=none#Reality-TCP-Vision-IPv6"
                echo -e "${green}【类型 1】 Vless + TCP + Reality + Vision (分配端口: ${p_v})：${plain}"
                echo ""
                echo -e "\033[1;35m${link_vision}${plain}"
                echo ""
            fi

            # 创建类型 2: VLESS + XHTTP + Reality (已完整包含 path 和 mode=stream-up 参数)
            if [[ "$v6_choice" == "2" || "$v6_choice" == "3" ]]; then
                local p_x=$([[ "$v6_choice" == "3" ]] && echo "$port_xhttp" || echo "$port_vision")
                local remark_x="IPv6-XHTTP-$p_x"
                local tag_x="v6-xhttp-$p_x"
                local settings_x="{\"clients\":[{\"id\":\"$uuid\",\"flow\":\"\",\"email\":\"$remark_x\",\"level\":0,\"enable\":true}],\"decryption\":\"none\",\"fallbacks\":[]}"
                local stream_x="{\"network\":\"xhttp\",\"security\":\"reality\",\"realitySettings\":{\"show\":false,\"target\":\"${sni}:443\",\"xver\":0,\"serverNames\":[\"$sni\",\"www.$sni\"],\"settings\":{\"publicKey\":\"$pbk\",\"spiderX\":\"/\",\"mldsa65Verify\":\"\"},\"privateKey\":\"$priv\",\"maxClientVer\":\"\",\"minClientVer\":\"\",\"maxTimediff\":0,\"mldsa65Seed\":\"\",\"shortIds\":[\"$sid\"]},\"xhttpSettings\":{\"headers\":{},\"host\":\"\",\"mode\":\"stream-up\",\"noSSEHeader\":false,\"path\":\"/${xhttp_rand_path}\",\"scMaxBufferedPosts\":30,\"scMaxEachPostBytes\":\"1000000\",\"scStreamUpServerSecs\":\"20-80\",\"xPaddingBytes\":\"100-1000\"}}"
                
                # 写入面板数据库，打通后台入站数据
                if [ -f "/etc/x-ui/x-ui.db" ]; then
                    sqlite3 /etc/x-ui/x-ui.db "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, 0, '$remark_x', 1, 0, '::', $p_x, 'vless', '$settings_x', '$stream_x', '$tag_x', '$sniffing_json');"
                fi

                local link_xhttp="vless://${uuid}@[${v6}]:${p_x}?encryption=none&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&spx=%2F&type=xhttp&path=%2F${xhttp_rand_path}&mode=stream-up#Reality-XHTTP-IPv6"
                echo -e "${green}【类型 2】 VLESS + XHTTP + Reality (分配端口: ${p_x})：${plain}"
                echo ""
                echo -e "\033[1;35m${link_xhttp}${plain}"
                echo ""
            fi

            sleep 1
            # 自动重启面板服务，使数据库中的新入站配置在 Xray 核心中正式生效监听
            LOGI "正在自动重启面板以生效新创建的 IPv6 入站配置......"
            systemctl restart x-ui >/dev/null 2>&1
            echo ""

            sleep 1
            # 3. 自动调用 UFW 防火墙工具放行对应端口
            if command -v ufw &> /dev/null; then
                if [[ "$v6_choice" == "1" || "$v6_choice" == "3" ]]; then
                    ufw allow ${port_vision} >/dev/null 2>&1
                    LOGI "已自动通过 UFW 防火墙放行端口: ${port_vision}"
                    echo ""
                fi
                if [[ "$v6_choice" == "2" || "$v6_choice" == "3" ]]; then
                    local p_allow_x=$([[ "$v6_choice" == "3" ]] && echo "$port_xhttp" || echo "$port_vision")
                    ufw allow ${p_allow_x} >/dev/null 2>&1
                    LOGI "已自动通过 UFW 防火墙放行端口: ${p_allow_x}"
                fi
            fi
            echo ""

            sleep 1
            # 4. 给出使用提示
            echo -e "${yellow}================================================================${plain}"
            echo -e "${green}------->>> 使用方法/说明提示：${plain}"
            echo -e "请复制上面“带 IPv6 的链接地址”，直接导入 “v2rayN” 等软件中即可使用。"
            echo -e "${yellow}================================================================${plain}"
            echo ""

            if [[ $# -eq 0 ]]; then
                before_show_menu
            fi
            ;;
        *)
            LOGE "无效选项，请重新输入！"
            create_ipv6_links
            ;;
    esac
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
  ${green}22.${plain} 启用 BBR 
——————————————————————
  ${green}23.${plain} 更新 Geo 文件
  ${green}24.${plain} Speedtest by Ookla
  ${green}25.${plain} 安装订阅转换
  ${green}26.${plain} 网页版SSH工具
  ${green}27.${plain} 线路和IP检测
  ${green}28.${plain} 服务器DNS检测
——————————————————————
  ${green}29.${plain} 系统调优(TCP/BBR)
  ${green}30.${plain} 远程备份/急救还原
  ${green}31.${plain} 面板数据库一键迁移
  ${green}32.${plain} Cloudflare Argo 隧道(防失联)
  ${green}33.${plain} 自动创建 IPv6 链接（应急防封）
——————————————————————
  ${green}若在使用过程中有任何问题${plain}
  ${yellow}请加入〔X-Panel-Pro 面板〕专属VIP群${plain}
  ${red}https://t.me/X_Panels ${yellow}截图进行反馈${plain}
  ${green}〔X-Panel 面板〕项目地址${plain}
  ${yellow}https://github.com/xeefei/x-panel${plain}
  ${green}详细〔安装配置〕教程${plain}
  ${yellow}https://xeefei.blogspot.com/2025/09/x-panel.html${plain}
——————————————————————

-------------->>>>>>>赞 助 推 广 区<<<<<<<<-------------------

${green}1、搬瓦工GIA高端线路：${yellow}https://bandwagonhost.com/aff.php?aff=75015${plain}

${green}2、Dmit高端GIA线路：${yellow}https://www.dmit.io/aff.php?aff=9326${plain}

${green}3、Gomami亚太顶尖优化线路：${yellow}https://gomami.io/aff.php?aff=174${plain}

${green}4、ISIF优质亚太优化线路：${yellow}https://cloud.isif.net/login?affiliation_code=333${plain}

${green}5、ZoroCloud全球优质原生家宽&住宅双lSP，跨境首选：${yellow}https://my.zorocloud.com/aff.php?aff=1072${plain}

${green}6、三网直连 IEPL / IPLC 直播流量转发：${yellow}https://idc333.top/#register/BCUZXNELNO${plain}

${green}7、Bagevm优质落地鸡（原生IP全解锁）：${yellow}https://www.bagevm.com/aff.php?aff=754${plain}

${green}8、白丝云〔4837线路〕实惠量大管饱：${yellow}https://cloudsilk.io/aff.php?aff=706${plain}

${green}9、RackNerd极致性价比机器：${yellow}https://my.racknerd.com/aff.php?aff=15268&pid=912${plain}

----------------------------------------------
"
    show_status
    echo && read -p "请输入数字选项 [0-33]: " num

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
    26)
        check_install && install_sshwifty
        ;;
    27)
        check_install && check_place_menu
        ;;
    28)
        check_install && dns_check
        ;;
    29)
        check_install && system_tuning_menu
        ;;
    30)
        check_install && backup_restore_menu
        ;;
    31)
        check_install && migrate_database
        ;;
    32)
        check_install && argo_tunnel_menu
        ;;
    33)
        check_install && create_ipv6_links
        ;;
    *)
        LOGE "请输入正确的数字选项 [0-33]"
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
    "sshwifty")
        check_install 0 && install_sshwifty 0 
        ;;
    "dnscheck")
        check_install 0 && dns_check 0
        ;;
    "tune")
        check_install 0 && system_tuning_menu 0
        ;;
    "backup")
        check_install 0 && remote_backup 0
        ;;
    "restore")
        check_install 0 && rescue_restore 0
        ;;
    "migrate")
        check_install 0 && migrate_database 0
        ;;
    "argo")
        check_install 0 && argo_tunnel_menu 0
        ;;
    "ipv6")
        check_install 0 && create_ipv6_links 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
