#!/bin/bash

show_limited_ports() {
    echo "当前接口 $INTERFACE 已限速的端口："
    sudo tc filter show dev $INTERFACE | grep -Eo "sport .*|dport .*" | awk '{print "端口: " $2}'
}

add_limit() {
    read -p "请输入要限速的端口号 (例如, 8080): " PORT
    if [ -z "$PORT" ]; then
        echo "端口号不能为空，请重试。"
        return
    fi

    # 检查是否已存在该端口的限速规则
    EXISTING_RULE=$(sudo tc filter show dev $INTERFACE | grep -E "match ip (sport|dport) $PORT")
    if [ -n "$EXISTING_RULE" ]; then
        echo "端口 $PORT 已存在限速规则，将被覆盖。"
        delete_limit $PORT
    fi

    read -p "请输入上传速度限制 (例如, 10, 默认单位是 mbit/s): " UPLOAD_SPEED
    if [[ ! "$UPLOAD_SPEED" =~ [a-zA-Z]+$ ]]; then
        UPLOAD_SPEED="${UPLOAD_SPEED}mbit"
    fi

    read -p "请输入下载速度限制 (例如, 500, 默认单位是 mbit/s): " DOWNLOAD_SPEED
    if [[ ! "$DOWNLOAD_SPEED" =~ [a-zA-Z]+$ ]]; then
        DOWNLOAD_SPEED="${DOWNLOAD_SPEED}mbit"
    fi

    # 设置根队列规则
    sudo tc qdisc add dev $INTERFACE root handle 1: htb default 30 2>/dev/null

    # 创建一个主类，带有最大带宽限制
    sudo tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1000mbit 2>/dev/null

    # 为上传和下载创建子类，带有限速
    sudo tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $UPLOAD_SPEED 2>/dev/null
    sudo tc class add dev $INTERFACE parent 1:1 classid 1:20 htb rate $DOWNLOAD_SPEED 2>/dev/null

    # 过滤指定端口的流量
    sudo tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip sport $PORT 0xffff flowid 1:10
    sudo tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dport $PORT 0xffff flowid 1:20

    echo "端口 $PORT 在接口 $INTERFACE 上的上传限速为 $UPLOAD_SPEED，下载限速为 $DOWNLOAD_SPEED。"
}

delete_limit() {
    PORT=$1
    if [ -z "$PORT" ]; then
        read -p "请输入要删除限速的端口号 (例如, 8080): " PORT
    fi

    if [ -z "$PORT" ]; then
        echo "端口号不能为空，请重试。"
        return
    fi

    # 检查是否存在该端口的限速规则
    EXISTING_RULE=$(sudo tc filter show dev $INTERFACE | grep -E "match ip (sport|dport) $PORT")
    if [ -z "$EXISTING_RULE" ]; then
        echo "端口 $PORT 未找到限速规则。"
        return
    fi

    # 删除指定端口的过滤规则
    sudo tc filter del dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip sport $PORT 0xffff
    sudo tc filter del dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dport $PORT 0xffff

    echo "已删除接口 $INTERFACE 上端口 $PORT 的限速。"
}

reset_all_limits() {
    sudo tc qdisc del dev $INTERFACE root
    echo "已删除接口 $INTERFACE 上的所有限速规则。"
}

main_menu() {
    while true; do
        echo "网络接口: $INTERFACE"
        echo "1. 显示当前限速端口"
        echo "2. 添加新的端口限速"
        echo "3. 删除端口限速规则"
        echo "4. 重置所有限速规则"
        echo "5. 退出脚本"
        read -p "请选择一个选项: " option

        case $option in
            1) show_limited_ports ;;
            2) add_limit ;;
            3) delete_limit ;;
            4) reset_all_limits ;;
            5) exit 0 ;;
            *) echo "无效选项，请重试。" ;;
        esac
    done
}

# 获取输入的网络接口
read -p "请输入网络接口名称 (例如, eth0): " INTERFACE

if [ -z "$INTERFACE" ]; then
    echo "网络接口名称是必填项，程序将退出。"
    exit 1
fi

main_menu
