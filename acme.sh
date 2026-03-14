#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

# 设置错误处理
set -e
set -o pipefail

# 颜色输出函数
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 输入验证函数 - 防止命令注入
validate_input() {
    local input="$1"
    local name="$2"
    
    # 检查是否包含危险字符
    if [[ "$input" =~ [\;\|\&\$\`\(\)\{\}\[\]\*\?\>\<] ]]; then
        red "错误: ${name} 包含非法字符，已拒绝"
        exit 1
    fi
    
    # 检查是否为空
    if [[ -z "$input" ]]; then
        red "错误: ${name} 不能为空"
        exit 1
    fi
    
    echo "$input"
}

# 域名验证函数
validate_domain() {
    local domain="$1"
    
    # 检查是否包含非法字符
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9]$ ]]; then
        red "错误: 域名格式不正确"
        exit 1
    fi
    
    # 检查长度
    if [[ ${#domain} -gt 253 ]]; then
        red "错误: 域名过长"
        exit 1
    fi
    
    echo "$domain"
}

# IP地址验证函数
validate_ip() {
    local ip="$1"
    
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        red "错误: IP地址格式不正确"
        exit 1
    fi
    
    echo "$ip"
}

# 端口验证函数
validate_port() {
    local port="$1"
    
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        red "错误: 端口号必须在 1-65535 之间"
        exit 1
    fi
    
    echo "$port"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意：请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i"
    if [[ -n $SYS ]]; then
        break
    fi
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        if [[ -n $SYSTEM ]]; then
            break
        fi
    fi
done

[[ -z $SYSTEM ]] && red "不支持当前VPS系统, 请使用主流的操作系统" && exit 1

# 脚本更新函数
update_script() {
    yellow "正在检查更新..."
    
    # 获取当前脚本路径
    script_path="$(readlink -f "$0")"
    script_dir="$(dirname "$script_path")"
    
    # 尝试从GitHub拉取最新版本
    green "正在从 GitHub 拉取最新版本..."
    
    # 备份当前脚本
    cp "$script_path" "${script_path}.backup.$(date +%Y%m%d%H%M%S)"
    
    # 尝试多种下载方式
    if curl -sSL "https://raw.githubusercontent.com/lwhx/vp/refs/heads/lwhx/acme.sh" -o "$script_path" 2>/dev/null; then
        green "脚本更新成功！"
    elif curl -sSL "https://raw.githubusercontent.com/lwhx/vp/main/acme.sh" -o "$script_path" 2>/dev/null; then
        green "脚本更新成功！"
    elif wget -q "https://raw.githubusercontent.com/lwhx/vp/refs/heads/lwhx/acme.sh" -O "$script_path" 2>/dev/null; then
        green "脚本更新成功！"
    else
        # 尝试使用git pull
        if [[ -d "$script_dir/.git" ]]; then
            yellow "尝试使用 git pull 更新..."
            cd "$script_dir"
            if git pull origin lwhx 2>/dev/null; then
                green "脚本更新成功！"
            else
                red "更新失败，请检查网络连接或手动更新"
                cd -
            fi
        else
            red "更新失败，请检查网络连接或手动更新"
        fi
    fi
    
    # 设置执行权限
    chmod +x "$script_path"
    
    # 显示新版本信息
    if [[ -f "$script_path" ]]; then
        green "脚本已更新到最新版本！"
        yellow "如需使用新版本，请重新运行脚本"
    fi
    
    back2menu
}

back2menu() {
    echo ""
    green "所选命令操作执行完成"
    read -rp "请输入“y”退出, 或按任意键回到主菜单：" back2menuInput
    case "$back2menuInput" in
        y) exit 1 ;;
        *) menu ;;
    esac
}

install_base(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl 
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} cronie bind-utils
        systemctl start crond
        systemctl enable crond
    else
        ${PACKAGE_INSTALL[int]} cron dnsutils
        systemctl start cron
        systemctl enable cron
    fi
}

install_acme(){
    install_base
    
    # 检查 curl 是否可用
    if [[ -z $(type -P curl) ]]; then
        red "curl 未安装，请先安装 curl 后再运行脚本"
        ${PACKAGE_INSTALL[int]} curl
    fi
    
    read -rp "请输入注册邮箱 (例: admin@gmail.com, 或留空自动生成一个gmail邮箱): " acmeEmail
    
    # 如果用户未输入邮箱，则自动生成
    if [[ -z $acmeEmail ]]; then
        autoEmail=$(date +%s%N | md5sum | cut -c 1-16)
        acmeEmail=$autoEmail@gmail.com
        yellow "已取消设置邮箱, 使用自动生成的gmail邮箱: $acmeEmail"
    fi
    
    # 安装acme.sh
    yellow "正在安装 Acme.sh..."
    if curl -sSL https://get.acme.sh | sh -s email=$acmeEmail; then
        green "Acme.sh 安装命令执行成功"
    else
        red "Acme.sh 安装命令执行失败，请检查网络连接"
        back2menu
    fi
    
    source ~/.bashrc
    
    # 检查 acme.sh 是否安装成功
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        red "Acme.sh 安装失败，未找到安装文件"
        back2menu
    fi
    
    # 升级acme.sh并启用自动升级
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null
    
    # 设置默认CA为Let's Encrypt
    bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null
    
    # 验证安装是否成功
    if [[ -n $(~/.acme.sh/acme.sh -v 2>/dev/null) ]]; then
        green "Acme.sh证书申请脚本安装成功!"
    else
        red "抱歉, Acme.sh证书申请脚本安装失败"
        green "建议如下："
        yellow "1. 检查VPS的网络环境"
        yellow "2. 脚本可能跟不上时代, 建议截图发布到GitHub Issues询问"
    fi
    back2menu
}

check_80(){
    # 检查 lsof 是否已安装
    if [[ -z $(type -P lsof) ]]; then
        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} lsof
    fi
    
    yellow "正在检测80端口是否占用..."
    sleep 1
    
    # 检测 80 端口是否被占用
    if [[ $(lsof -i:"80" 2>/dev/null | grep -i -c "listen") -eq 0 ]]; then
        green "检测到目前80端口未被占用"
        sleep 1
    else
        red "检测到目前80端口被其他程序占用，以下为占用程序信息"
        lsof -i:"80"
        read -rp "如需结束占用进程请按Y，按其他键则退出 [Y/N]: " yn
        if [[ $yn =~ ^[Yy]$ ]]; then
            lsof -i:"80" | awk '{print $2}' | grep -v "PID" | xargs kill -9 2>/dev/null
            sleep 1
        else
            exit 1
        fi
    fi
    
    # 配置防火墙规则
    if [[ $SYSTEM == "CentOS" ]]; then
        firewall-cmd --permanent --add-port=80/tcp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        green "TCP/80端口已开启"
    else
        if command -v ufw &> /dev/null; then
            ufw allow 80/tcp 2>/dev/null
            ufw reload 2>/dev/null
            green "TCP/80端口已开启"
        fi
    fi
}

acme_standalone(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装acme.sh, 无法执行操作" && exit 1
    
    # 检测80端口
    check_80
    
    # 检测WARP状态并临时关闭
    WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep warp | cut -d= -f2)
    WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep warp | cut -d= -f2)
    if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
    fi
    
    # 获取并缓存IP地址
    ipv4=$(curl -s4m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    ipv6=$(curl -s6m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    
    echo ""
    yellow "在使用80端口申请模式时, 请先将您的域名解析至你的VPS的真实IP地址, 否则会导致证书申请失败"
    echo ""
    
    # 显示IP地址
    if [[ -n $ipv4 && -n $ipv6 ]]; then
        echo -e "VPS的真实IPv4地址为: ${GREEN} $ipv4 ${PLAIN}"
        echo -e "VPS的真实IPv6地址为: ${GREEN} $ipv6 ${PLAIN}"
    elif [[ -n $ipv4 && -z $ipv6 ]]; then
        echo -e "VPS的真实IPv4地址为: ${GREEN} $ipv4 ${PLAIN}"
    elif [[ -z $ipv4 && -n $ipv6 ]]; then
        echo -e "VPS的真实IPv6地址为: ${GREEN} $ipv6 ${PLAIN}"
    fi
    
    echo ""
    read -rp "请输入解析完成的域名: " domain
    domain=$(validate_domain "${domain}")
    
    green "已输入的域名：$domain" && sleep 1
    
    # 获取域名解析的IP
    domainIP=$(dig +short "${domain}" 2>/dev/null)
    
    # 验证域名解析结果
    if [[ -z "$domainIP" ]]; then
        red "域名解析失败，请检查域名是否正确填写或等待DNS解析完成"
        exit 1
    fi
    
    # 检查是否解析到nginx（域名解析错误）
    if [[ -n $(echo "$domainIP" | grep nginx) ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            wg-quick up wgcf >/dev/null 2>&1
        fi
        if [[ -a "/opt/warp-go/warp-go" ]]; then
            systemctl start warp-go 
        fi
        yellow "域名解析失败, 请检查域名是否正确填写或等待解析完成再执行脚本"
        exit 1
    fi
    
    # 检查IP是否匹配
    if [[ -n $(echo "$domainIP" | grep ":") || -n $(echo "$domainIP" | grep ".") ]]; then
        if [[ "$domainIP" != "$ipv4" ]] && [[ "$domainIP" != "$ipv6" ]]; then
            if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
            fi
            if [[ -a "/opt/warp-go/warp-go" ]]; then
                systemctl start warp-go 
            fi
            green "域名 ${domain} 目前解析的IP: ($domainIP)"
            red "当前域名解析的IP与当前VPS使用的真实IP不匹配"
            green "建议如下："
            yellow "1. 请确保CloudFlare小云朵为关闭状态(仅限DNS), 其他域名解析或CDN网站设置同理"
            yellow "2. 请检查DNS解析设置的IP是否为VPS的真实IP"
            yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            exit 1
        fi
    fi
    
    # 根据IP版本申请证书
    if [[ "$domainIP" == "$ipv6" ]]; then
        bash ~/.acme.sh/acme.sh --issue -d "${domain}" --standalone -k ec-256 --listen-v6 --insecure
    fi
    
    if [[ "$domainIP" == "$ipv4" ]]; then
        bash ~/.acme.sh/acme.sh --issue -d "${domain}" --standalone -k ec-256 --insecure
    fi
    
    # 安装证书
    mkdir -p /root/${domain}
    bash ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /root/${domain}/private.key --fullchain-file /root/${domain}/cert.crt --ecc
    checktls "${domain}"
}

acme_cfapiTLD(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装Acme.sh, 无法执行操作" && exit 1
    
    # 获取IP地址（仅用于显示）
    ipv4=$(curl -s4m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    ipv6=$(curl -s6m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    
    read -rp "请输入需要申请证书的域名: " domain
    domain=$(validate_domain "${domain}")
    
    if [[ $(echo ${domain:0-2}) =~ cf|ga|gq|ml|tk ]]; then
        red "检测为Freenom免费域名, 由于CloudFlare API不支持, 故无法使用本模式申请!"
        back2menu
    fi
    
    read -rp "请输入CloudFlare Global API Key: " GAK
    GAK=$(validate_input "${GAK}" "CloudFlare Global API Key")
    export CF_Key="$GAK"
    
    read -rp "请输入CloudFlare的登录邮箱: " CFemail
    CFemail=$(validate_input "${CFemail}" "CloudFlare登录邮箱")
    export CF_Email="$CFemail"
    
    # API模式不需要检测80端口，直接申请证书
    yellow "正在使用CloudFlare API申请证书..."
    sleep 1
    
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --listen-v6 --insecure
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "${domain}" -k ec-256 --insecure
    fi
    
    mkdir -p /root/${domain}
    bash ~/.acme.sh/acme.sh --install-cert -d "${domain}" --key-file /root/${domain}/private.key --fullchain-file /root/${domain}/cert.crt --ecc
    checktls "${domain}"
}

acme_cfapiNTLD(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && red "未安装acme.sh, 无法执行操作" && exit 1
    
    # 获取IP地址（仅用于显示）
    ipv4=$(curl -s4m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    ipv6=$(curl -s6m8 ip.p3terx.com -k 2>/dev/null | sed -n 1p)
    
    read -rp "请输入需要申请证书的泛域名 (输入格式：example.com): " domain
    domain=$(validate_domain "${domain}")
    
    if [[ $(echo ${domain:0-2}) =~ cf|ga|gq|ml|tk ]]; then
        red "检测为Freenom免费域名, 由于CloudFlare API不支持, 故无法使用本模式申请!"
        back2menu
    fi
    
    read -rp "请输入CloudFlare Global API Key: " GAK
    GAK=$(validate_input "${GAK}" "CloudFlare Global API Key")
    export CF_Key="$GAK"
    
    read -rp "请输入CloudFlare的登录邮箱: " CFemail
    CFemail=$(validate_input "${CFemail}" "CloudFlare登录邮箱")
    export CF_Email="$CFemail"
    
    # API模式不需要检测80端口，直接申请证书
    yellow "正在使用CloudFlare API申请泛域名证书..."
    sleep 1
    
    if [[ -z $ipv4 ]]; then
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256 --listen-v6 --insecure
    else
        bash ~/.acme.sh/acme.sh --issue --dns dns_cf -d "*.${domain}" -d "${domain}" -k ec-256 --insecure
    fi
    
    mkdir -p /root/${domain}
    bash ~/.acme.sh/acme.sh --install-cert -d "*.${domain}" --key-file /root/${domain}/private.key --fullchain-file /root/${domain}/cert.crt --ecc
    checktls "${domain}"
}

checktls() {
domain=$1  # 从参数获取域名
    if [[ -f /root/${domain}/cert.crt && -f /root/${domain}/private.key ]]; then
        if [[ -s /root/${domain}/cert.crt && -s /root/${domain}/private.key ]]; then
            if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
            fi
            if [[ -a "/opt/warp-go/warp-go" ]]; then
                systemctl start warp-go 
            fi
            echo $domain > /root/${domain}/ca.log
            sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
            echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
            green "证书申请成功! 脚本申请到的证书 (cert.crt) 和私钥 (private.key) 文件已保存到 /root/${domain} 文件夹下"
            yellow "证书crt文件路径如下: /root/${domain}/cert.crt"
            yellow "私钥key文件路径如下: /root/${domain}/private.key"
            back2menu
        else
            if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
                wg-quick up wgcf >/dev/null 2>&1
            fi
            if [[ -a "/opt/warp-go/warp-go" ]]; then
                systemctl start warp-go 
            fi
            red "很抱歉，证书申请失败"
            green "建议如下: "
            yellow "1. 自行检测防火墙否打开, 如使用80端口申请模式时, 请关闭防火墙或放行80端口"
            yellow "2. 同一域名多次申请可能会触发Let's Encrypt官方风控, 请尝试使用脚本菜单的9选项更换证书颁发机构, 再重试申请证书, 或更换域名、或等待7天后再尝试执行脚本"
            yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues询问"
            back2menu
        fi
    fi
}

view_cert(){
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh, 无法执行操作!" && exit 1
    bash ~/.acme.sh/acme.sh --list
    back2menu
}

revoke_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh, 无法执行操作!" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -rp "请输入要撤销的域名证书 (复制Main_Domain下显示的域名): " domain
    domain=$(validate_domain "${domain}")
    
    if [[ -n $(bash ~/.acme.sh/acme.sh --list 2>/dev/null | grep "${domain}") ]]; then
        bash ~/.acme.sh/acme.sh --revoke -d "${domain}" --ecc 2>/dev/null
        bash ~/.acme.sh/acme.sh --remove -d "${domain}" --ecc 2>/dev/null
        rm -rf ~/.acme.sh/${domain}_ecc 2>/dev/null
        rm -f /root/${domain}/cert.crt /root/${domain}/private.key 2>/dev/null
        green "撤销${domain}的域名证书成功"
        back2menu
    else
        red "未找到${domain}的域名证书, 请自行检查!"
        back2menu
    fi
}

renew_cert() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装acme.sh, 无法执行操作!" && exit 1
    bash ~/.acme.sh/acme.sh --list
    read -rp "请输入要续期的域名证书 (复制Main_Domain下显示的域名): " domain
    domain=$(validate_domain "${domain}")
    
    if [[ -n $(bash ~/.acme.sh/acme.sh --list 2>/dev/null | grep "${domain}") ]]; then
        bash ~/.acme.sh/acme.sh --renew -d "${domain}" --force --ecc 2>/dev/null
        checktls "${domain}"
        back2menu
    else
        red "未找到${domain}的域名证书，请再次检查域名输入正确"
        back2menu
    fi
}

switch_provider(){
    yellow "请选择证书提供商, 默认通过 Letsencrypt.org 来申请证书 "
    yellow "如果证书申请失败, 例如一天内通过 Letsencrypt.org 申请次数过多, 可选 BuyPass.com 或 ZeroSSL.com 来申请."
    echo -e " ${GREEN}1.${PLAIN} Letsencrypt.org"
    echo -e " ${GREEN}2.${PLAIN} BuyPass.com"
    echo -e " ${GREEN}3.${PLAIN} ZeroSSL.com"
    read -rp "请选择证书提供商 [1-3，默认1]: " provider
    case $provider in
        2) bash ~/.acme.sh/acme.sh --set-default-ca --server buypass && green "切换证书提供商为 BuyPass.com 成功！" ;;
        3) bash ~/.acme.sh/acme.sh --set-default-ca --server zerossl && green "切换证书提供商为 ZeroSSL.com 成功！" ;;
        *) bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt && green "切换证书提供商为 Letsencrypt.org 成功！" ;;
    esac
    
    back2menu
}

uninstall() {
    [[ -z $(~/.acme.sh/acme.sh -v 2>/dev/null) ]] && yellow "未安装Acme.sh, 卸载程序无法执行!" && exit 1
    ~/.acme.sh/acme.sh --uninstall
    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
    rm -rf ~/.acme.sh
    green "Acme  一键申请证书脚本已彻底卸载!"
}

create_nginx_config() {
    # 检查是否安装了nginx
    if ! command -v nginx &> /dev/null; then
        yellow "检测到未安装nginx，正在安装..."
        if [[ $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_INSTALL[int]} nginx
        else
            ${PACKAGE_UPDATE[int]}
            ${PACKAGE_INSTALL[int]} nginx
        fi
        systemctl start nginx
        systemctl enable nginx
    fi

    # 创建必要的目录
    mkdir -p /etc/nginx/sites-available/
    mkdir -p /etc/nginx/sites-enabled/

    # 确保nginx配置文件包含sites-enabled目录
    if ! grep -q "include /etc/nginx/sites-enabled/\*;" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \    include /etc/nginx/sites-enabled/\*;' /etc/nginx/nginx.conf
    fi

    # 获取并验证用户输入
    read -rp "请输入域名: " domain
    domain=$(validate_domain "${domain}")
    
    read -rp "请输入反向代理IP: " proxy_ip
    proxy_ip=$(validate_ip "${proxy_ip}")
    
    read -rp "请输入反向代理端口: " proxy_port
    proxy_port=$(validate_port "${proxy_port}")

    # 检查证书文件是否存在
    if [[ ! -f /root/${domain}/cert.crt || ! -f /root/${domain}/private.key ]]; then
        red "未找到该域名的SSL证书文件，请先申请证书！"
        back2menu
    fi

    # 检测 Nginx 是否支持 HTTP/3 和 HTTP/2
    nginx_version=$(nginx -v 2>&1 | grep -oP '\d+\.\d+(\.\d+)?')
    http3_enabled=false
    http2_enabled=false
    
    # 获取 Nginx 编译信息（大写 V 输出到 stderr）
    nginx_compile_info=$(nginx -V 2>&1)
    
    if echo "$nginx_compile_info" | grep -q "with-http_v3_module"; then
        http3_enabled=true
        green "检测到 Nginx 支持 HTTP/3"
    fi
    
    if echo "$nginx_compile_info" | grep -q "with-http_v2_module"; then
        http2_enabled=true
        green "检测到 Nginx 支持 HTTP/2"
    fi
    
    # 根据检测结果生成不同的配置
    if [[ "$http3_enabled" == "true" ]]; then
        # HTTP/3 配置
        cat > /etc/nginx/sites-available/${domain} << 'NGINX_EOF'
# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name __SERVER_NAME__;
    
    # 重定向到 HTTPS
    return 301 https://__SERVER_NAME__$request_uri;
}

# HTTPS 服务器配置 (HTTP/3)
server {
    listen 443 ssl http3;
    listen [::]:443 ssl http3;
    server_name __SERVER_NAME__;

    # SSL 证书配置
    ssl_certificate /__CERT_PATH__/cert.crt;
    ssl_certificate_key /__CERT_PATH__/private.key;
    
    # SSL 协议和加密套件
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    
    # SSL 会话优化
    ssl_session_cache shared:SSL:30m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    ssl_buffer_size 32k;
    
    # HTTP/2 和 HTTP/3 配置（已在 listen 中启用，此处可配置并发流）
    http2_max_concurrent_streams 512;
    http3_max_concurrent_streams 512;
    
    # 安全头部
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=()" always;
    add_header Vary "Accept-Encoding" always;

    # Gzip 压缩
    gzip on;
    gzip_static on;
    gzip_comp_level 3;
    gzip_buffers 8 256k;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/javascript application/javascript application/json application/xml text/xml application/rss+xml application/atom+xml image/svg+xml font/woff font/woff2 application/wasm;
    gzip_vary on;
    gzip_proxied any;
    gzip_disable "msie6";

    # 反向代理配置
    location / {
        proxy_pass http://__PROXY_IP__:__PROXY_PORT__;
        
        # 代理头部设置
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # 代理超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 代理缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 8 16k;
        proxy_busy_buffers_size 32k;
        
        # 保持连接
        proxy_socket_keepalive on;
    }
}
NGINX_EOF
    elif [[ "$http2_enabled" == "true" ]]; then
        yellow "当前 Nginx 版本不支持 HTTP/3，将使用 HTTP/2"
        # HTTP/2 配置（兼容不支持 HTTP/3 的 Nginx）
        cat > /etc/nginx/sites-available/${domain} << 'NGINX_EOF'
# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name __SERVER_NAME__;
    
    # 重定向到 HTTPS
    return 301 https://__SERVER_NAME__$request_uri;
}

# HTTPS 服务器配置 (HTTP/2)
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name __SERVER_NAME__;

    # SSL 证书配置
    ssl_certificate /__CERT_PATH__/cert.crt;
    ssl_certificate_key /__CERT_PATH__/private.key;
    
    # SSL 协议和加密套件
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    
    # SSL 会话优化
    ssl_session_cache shared:SSL:30m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    ssl_buffer_size 32k;
    
    # HTTP/2 配置（已在 listen 中启用，此处可配置并发流）
    http2_max_concurrent_streams 512;
    
    # 安全头部
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=()" always;
    add_header Vary "Accept-Encoding" always;

    # Gzip 压缩
    gzip on;
    gzip_static on;
    gzip_comp_level 3;
    gzip_buffers 8 256k;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/javascript application/javascript application/json application/xml text/xml application/rss+xml application/atom+xml image/svg+xml font/woff font/woff2 application/wasm;
    gzip_vary on;
    gzip_proxied any;
    gzip_disable "msie6";

    # 反向代理配置
    location / {
        proxy_pass http://__PROXY_IP__:__PROXY_PORT__;
        
        # 代理头部设置
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # 代理超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 代理缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 8 16k;
        proxy_busy_buffers_size 32k;
        
        # 保持连接
        proxy_socket_keepalive on;
    }
}
NGINX_EOF
    else
        # 纯 HTTPS 配置（不支持 HTTP/2 和 HTTP/3）
        yellow "当前 Nginx 版本不支持 HTTP/2 和 HTTP/3，将使用纯 HTTPS"
        cat > /etc/nginx/sites-available/${domain} << 'NGINX_EOF'
# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name __SERVER_NAME__;
    
    # 重定向到 HTTPS
    return 301 https://__SERVER_NAME__$request_uri;
}

# HTTPS 服务器配置 (纯 HTTPS)
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name __SERVER_NAME__;

    # SSL 证书配置
    ssl_certificate /__CERT_PATH__/cert.crt;
    ssl_certificate_key /__CERT_PATH__/private.key;
    
    # SSL 协议和加密套件
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    
    # SSL 会话优化
    ssl_session_cache shared:SSL:30m;
    ssl_session_timeout 1h;
    ssl_session_tickets off;
    ssl_buffer_size 32k;
    
    # 安全头部
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Permissions-Policy "geolocation=(), microphone=()" always;
    add_header Vary "Accept-Encoding" always;

    # Gzip 压缩
    gzip on;
    gzip_static on;
    gzip_comp_level 3;
    gzip_buffers 8 256k;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/javascript application/javascript application/json application/xml text/xml application/rss+xml application/atom+xml image/svg+xml font/woff font/woff2 application/wasm;
    gzip_vary on;
    gzip_proxied any;
    gzip_disable "msie6";

    # 反向代理配置
    location / {
        proxy_pass http://__PROXY_IP__:__PROXY_PORT__;
        
        # 代理头部设置
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # 代理超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 代理缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 8 16k;
        proxy_busy_buffers_size 32k;
        
        # 保持连接
        proxy_socket_keepalive on;
    }
}
NGINX_EOF
    fi

    # 替换占位符为实际值
    sed -i "s|__SERVER_NAME__|${domain}|g" /etc/nginx/sites-available/${domain}
    sed -i "s|__PROXY_IP__|${proxy_ip}|g" /etc/nginx/sites-available/${domain}
    sed -i "s|__PROXY_PORT__|${proxy_port}|g" /etc/nginx/sites-available/${domain}
    sed -i "s|__CERT_PATH__|/root/${domain}|g" /etc/nginx/sites-available/${domain}

    # 检查配置文件是否创建成功
    if [[ ! -f /etc/nginx/sites-available/${domain} ]]; then
        red "配置文件创建失败！"
        back2menu
    fi

    # 创建符号链接
    ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/

    # 测试nginx配置
    if nginx -t; then
        systemctl reload nginx
        green "Nginx配置文件创建成功并已重新加载！"
    else
        red "Nginx配置测试失败，请检查配置文件！"
    fi
    
    back2menu
}

manage_nginx_config() {
    while true; do
        clear
        echo -e "${GREEN}Nginx配置文件管理${PLAIN}"
        echo "------------------------"
        
        # 检查sites-available目录是否存在
        if [[ ! -d /etc/nginx/sites-available ]]; then
            red "未找到 /etc/nginx/sites-available 目录！"
            back2menu
        fi

        # 获取配置文件列表（添加错误处理）
        configs=()
        if [[ -d /etc/nginx/sites-available ]]; then
            mapfile -t configs < <(ls /etc/nginx/sites-available/ 2>/dev/null)
        fi
        
        if [[ ${#configs[@]} -eq 0 ]] || [[ -z "${configs[0]}" ]]; then
            yellow "没有找到任何nginx配置文件！"
            back2menu
        fi

        echo "现有的nginx配置文件："
        for i in "${!configs[@]}"; do
            echo -e " ${GREEN}$((i+1)).${PLAIN} ${configs[$i]}"
        done
        echo "------------------------"
        echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
        
        read -rp "请选择要操作的配置文件 [0-${#configs[@]}]: " config_num
        
        if [[ "$config_num" == "0" ]]; then
            menu
            break
        fi
        
        if [[ ! $config_num =~ ^[0-9]+$ ]] || [[ $config_num -lt 1 ]] || [[ $config_num -gt ${#configs[@]} ]]; then
            red "输入错误！"
            continue
        fi

        selected_config=${configs[$((config_num-1))]}
        
        # 验证配置文件是否存在
        if [[ ! -f "/etc/nginx/sites-available/${selected_config}" ]]; then
            red "配置文件不存在或已被删除！"
            read -rp "按回车键继续..."
            continue
        fi
        while true; do
            clear
            echo -e "已选择: ${GREEN}${selected_config}${PLAIN}"
            echo "------------------------"
            echo -e "请选择操作："
            echo -e " ${GREEN}1.${PLAIN} 修改配置"
            echo -e " ${GREEN}2.${PLAIN} 删除配置"
            echo -e " ${GREEN}3.${PLAIN} 查看配置详情"
            echo -e " ${GREEN}4.${PLAIN} 返回配置文件列表"
            echo -e " ${GREEN}0.${PLAIN} 返回主菜单"
            
            read -rp "请选择 [0-4]: " operation
            case "$operation" in
                0)
                    menu
                    break 2
                    ;;
                1)
                    # 修改配置
                    if command -v vim &> /dev/null; then
                        vim "/etc/nginx/sites-available/${selected_config}"
                    else
                        ${PACKAGE_INSTALL[int]} vim
                        vim "/etc/nginx/sites-available/${selected_config}"
                    fi
                    
                    # 删除旧的符号链接并创建新的
                    rm -f "/etc/nginx/sites-enabled/${selected_config}"
                    ln -sf "/etc/nginx/sites-available/${selected_config}" "/etc/nginx/sites-enabled/"
                    
                    # 测试nginx配置
                    if nginx -t; then
                        systemctl reload nginx
                        green "配置已更新并重新加载！"
                    else
                        red "Nginx配置测试失败，请检查配置文件！"
                    fi
                    read -rp "按回车键继续..."
                    ;;
                2)
                    # 删除配置
                    read -rp "确认要删除此配置吗？[y/N]: " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        rm -f "/etc/nginx/sites-available/${selected_config}"
                        rm -f "/etc/nginx/sites-enabled/${selected_config}"
                        green "配置文件已删除！"
                        # 重新加载nginx
                        systemctl reload nginx
                        read -rp "按回车键继续..."
                        break  # 返回配置文件列表
                    else
                        yellow "已取消删除操作"
                        read -rp "按回车键继续..."
                    fi
                    ;;
                3)
                    # 查看配置详情
                    clear
                    echo -e "配置文件详情: ${GREEN}${selected_config}${PLAIN}"
                    echo "------------------------------------------------"
                    cat "/etc/nginx/sites-available/${selected_config}"
                    echo "------------------------------------------------"
                    read -rp "按回车键继续..."
                    ;;
                4)
                    break  # 返回配置文件列表
                    ;;
                *)
                    red "输入错误！"
                    read -rp "按回车键继续..."
                    ;;
            esac
        done
    done
}

menu() {
    clear
    echo "#######################################################################"
    echo -e "#                   ${RED}Acme  证书一键申请脚本${PLAIN}                            #"
    echo -e "# ${GREEN}作者${PLAIN}: 爱分享的小企鹅                                               #"
    echo -e "# ${GREEN}网站${PLAIN}: https://www.youtube.com/channel/UCLd2LDzFPFoUnuQsP8y1wRA      #"        
    echo "#######################################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 安装 Acme.sh 域名证书申请脚本"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Acme.sh 域名证书申请脚本${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 申请单域名证书 ${YELLOW}(80端口申请)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} 申请单域名证书 ${YELLOW}(CF API申请)${PLAIN} ${GREEN}(无需解析)${PLAIN} ${RED}(不支持freenom域名)${PLAIN}"
    echo -e " ${GREEN}5.${PLAIN} 申请泛域名证书 ${YELLOW}(CF API申请)${PLAIN} ${GREEN}(无需解析)${PLAIN} ${RED}(不支持freenom域名)${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}6.${PLAIN} 查看已申请的证书"
    echo -e " ${GREEN}7.${PLAIN} 撤销并删除已申请的证书"
    echo -e " ${GREEN}8.${PLAIN} 手动续期已申请的证书"
    echo -e " ${GREEN}9.${PLAIN} 切换证书颁发机构"
    echo -e " ${GREEN}10.${PLAIN} 创建Nginx反向代理配置"
    echo -e " ${GREEN}11.${PLAIN} 管理Nginx配置文件"
    echo " -------------"
    echo -e " ${GREEN}12.${PLAIN} ${YELLOW}更新脚本到最新版本${PLAIN}"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-12]: " NumberInput
    case "$NumberInput" in
        1) install_acme ;;
        2) uninstall ;;
        3) acme_standalone ;;
        4) acme_cfapiTLD ;;
        5) acme_cfapiNTLD ;;
        6) view_cert ;;
        7) revoke_cert ;;
        8) renew_cert ;;
        9) switch_provider ;;
        10) create_nginx_config ;;
        11) manage_nginx_config ;;
        12) update_script ;;
        *) exit 1 ;;
    esac
}

menu
