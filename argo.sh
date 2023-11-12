#!/bin/bash

# 控制台字体
red() {
	echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
	echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
	echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Alpine")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")

# 判断系统CPU架构
cpuArch=$(uname -m)

# 判断cloudflared状态
cloudflaredStatus="未安装"
loginStatus="未登录"

# 判断是否为root用户
[[ $EUID -ne 0 ]] && yellow "请在root用户下运行脚本" && exit 1

# 检测系统，本部分代码感谢fscarmen的指导
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
	SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
	[[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "不支持VPS的当前系统，请使用主流的操作系统" && exit 1
[[ -z $(type -P curl) ]] && ${PACKAGE_UPDATE[int} && ${PACKAGE_INSTALL[int]} curl


checkCentOS8() {
	if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
		yellow "检测到当前VPS系统为CentOS 8，是否升级为CentOS Stream 8以确保软件包正常安装？"
		read -p "请输入选项 [y/n]：" comfirmCentOSStream
		if [[ $comfirmCentOSStream == "y" ]]; then
			yellow "正在为你升级到CentOS Stream 8，大概需要10-30分钟的时间"
			sleep 1
			sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
			yum clean all && yum makecache
			dnf swap centos-linux-repos centos-stream-repos distro-sync -y
		else
			red "已取消升级过程，脚本即将退出！"
			exit 1
		fi
	fi
}

archAffix() {
	case "$cpuArch" in
		i686 | i386) cpuArch='386' ;;
		x86_64 | amd64) cpuArch='amd64' ;;
		armv5tel | arm6l | armv7 | armv7l) cpuArch='arm' ;;
		armv8 | aarch64) cpuArch='aarch64' ;;
		*) red "不支持的CPU架构！" && exit 1 ;;
	esac
}

back2menu() {
	green "所选操作执行完成"
	read -p "请输入“y”退出，或按任意键回到主菜单：" back2menuInput
	case "$back2menuInput" in
		y) exit 1 ;;
		*) menu ;;
	esac
}

checkStatus() {
	[[ -z $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="未安装"
	[[ -n $(cloudflared -help 2>/dev/null) ]] && cloudflaredStatus="已安装"
	[[ -f /root/.cloudflared/cert.pem ]] && loginStatus="已登录"
	[[ ! -f /root/.cloudflared/cert.pem ]] && loginStatus="未登录"
}

installCloudFlared() {
	[ $cloudflaredStatus == "已安装" ] && red "检测到已安装并登录CloudFlare Argo Tunnel，无需重复安装！！" && exit 1
	if [ ${RELEASE[int]} == "CentOS" ]; then
		[ $cpuArch == "amd64" ] && cpuArch="x86_64"
		wget -N https://ghproxy.com/https://github.com/xxf185/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.rpm
		rpm -i cloudflared-linux-$cpuArch.rpm
		rm -f cloudflared-linux-$cpuArch.rpm
	else
		[ $cpuArch == "aarch64" ] && cpuArch="arm64"
		wget -N https://ghproxy.com/https://github.com/xxf185/cloudflared/releases/latest/download/cloudflared-linux-$cpuArch.deb
		dpkg -i cloudflared-linux-$cpuArch.deb
		rm -f cloudflared-linux-$cpuArch.deb
	fi
	green "请访问下方提示的网址，登录自己的CloudFlare账号"
	green "然后授权自己的域名给CloudFlare Argo Tunnel即可"
	cloudflared tunnel login
	back2menu
}

uninstallCloudFlared() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	${PACKAGE_REMOVE[int]} cloudflared
	rm -rf /root/.cloudflared
	yellow "CloudFlared 客户端已卸载成功"
}

makeTunnel() {
	read -p "请输入需要创建的隧道名称：" tunnelName
	cloudflared tunnel create $tunnelName
	read -p "请输入域名：" tunnelDomain
	cloudflared tunnel route dns $tunnelName $tunnelDomain
	cloudflared tunnel list
	read -p "请输入隧道UUID（复制ID里面的内容）：" tunnelUUID
	read -p "请输入传输协议（默认http）：" tunnelProtocol
	[ -z $tunnelProtocol ] && tunnelProtocol="http"
	read -p "请输入反代端口（默认80）：" tunnelPort
	[ -z $tunnelPort ] && tunnelPort=80
	read -p "请输入将要保存的配置文件名：" tunnelFileName
	cat <<EOF >~/$tunnelFileName.yml
tunnel: $tunnelName
credentials-file: /root/.cloudflared/$tunnelUUID.json
originRequest:
  connectTimeout: 30s
  noTLSVerify: true
ingress:
  - hostname: $tunnelDomain
    service: $tunnelProtocol://localhost:$tunnelPort
  - service: http_status:404
EOF
	green "配置文件生成成功，已保存为 /root/$tunnelFileName.yml"
	back2menu
}

listTunnel() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	[ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
	cloudflared tunnel list
	back2menu
}

runTunnel() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	[ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
	[[ -z $(type -P screen) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} screen
	read -p "请复制粘贴配置文件的位置（例：/root/tunnel.yml）：" ymlLocation
	read -p "请输入创建Screen会话的名字：" screenName
	screen -USdm $screenName cloudflared tunnel --config $ymlLocation run
	green "隧道已运行成功，请等待1-3分钟启动并解析完毕"
	back2menu
}

killTunnel() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	[ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
	[[ -z $(type -P screen) ]] && ${PACKAGE_UPDATE[int]} && ${PACKAGE_INSTALL[int]} screen
	read -p "请输入需要删除的Screen会话名字：" screenName
	screen -S $screenName -X quit
	green "Screen会话停止成功！"
	back2menu
}

deleteTunnel() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	[ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
	read -p "请输入需要删除的隧道名称：" tunnelName
	cloudflared tunnel delete $tunnelName
	back2menu
}

argoCert() {
	[ $cloudflaredStatus == "未安装" ] && red "检测到未安装CloudFlare Argo Tunnel客户端，无法执行操作！！！" && exit 1
	[ $loginStatus == "未登录" ] && red "请登录CloudFlare Argo Tunnel客户端后再执行操作！！！" && exit 1
	sed -n "1, 5p" /root/.cloudflared/cert.pem >>/root/private.key
	sed -n "6, 24p" /root/.cloudflared/cert.pem >>/root/cert.crt
	green "CloudFlare Argo Tunnel证书提取成功！"
	yellow "证书crt路径如下：/root/cert.crt"
	yellow "私钥key路径如下：/root/private.key"
	green "使用证书提示："
	yellow "1. 当前证书只能使用于CF Argo Tunnel授权过的域名"
	yellow "2. 在需要使用证书的服务使用Argo Tunnel的域名，必须使用其证书"
	back2menu
}

menu() {
	clear
	checkStatus
	echo "                           "
	yellow  "==========CloudFlare Argo Tunnel一键脚本=========="
	echo "                           "
	green "CloudFlared 客户端状态：$cloudflaredStatus"
	green "账户登录状态：$loginStatus"
	echo "            "
	echo "1. 安装并登录CloudFlared客户端"
	echo "2. 配置Argo Tunnel隧道"
	echo "3. 列出Argo Tunnel隧道"
	echo "4. 运行Argo Tunnel隧道"
	echo "5. 停止Argo Tunnel隧道"
	echo "6. 删除Argo Tunnel隧道"
	echo "7. 获取Argo Tunnel证书"
	echo "8. 卸载CloudFlared客户端"
	echo "9. 更新脚本"
	echo "0. 退出脚本"
	echo "          "
	read -p "请输入选项:" menuNumberInput
	case "$menuNumberInput" in
		1) installCloudFlared ;;
		2) makeTunnel ;;
		3) listTunnel ;;
		4) runTunnel ;;
		5) killTunnel ;;
		6) deleteTunnel ;;
		7) argoCert ;;
		8) uninstallCloudFlared ;;
		9) wget -N --no-check-certificate https://raw.githubusercontent.com/xxf185/CloudFlare-Argo-Tunnel/master/argo.sh && bash argo.sh ;;
		*) exit 1 ;;
	esac
}

archAffix
checkCentOS8
menu
