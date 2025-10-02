#!/bin/bash

# LXD Web 管理后台构建脚本

echo "开始构建 LXD Web 管理后台..."
echo "使用纯 Go SQLite 驱动"
echo ""

# 清理旧文件
echo "清理旧文件..."
rm -f lxdweb lxdweb-amd64 lxdweb-arm64

BUILD_SUCCESS=0

# 构建 AMD64 版本
echo "构建 AMD64 版本..."
if CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o lxdweb-amd64 -ldflags="-s -w" main.go; then
    echo "AMD64 构建成功 ($(du -h lxdweb-amd64 | cut -f1))"
    BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
else
    echo "AMD64 构建失败"
fi

echo ""

# 构建 ARM64 版本
echo "构建 ARM64 版本..."
if CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o lxdweb-arm64 -ldflags="-s -w" main.go; then
    echo "ARM64 构建成功 ($(du -h lxdweb-arm64 | cut -f1))"
    BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
else
    echo "ARM64 构建失败"
fi

echo ""
echo "================================"

if [ $BUILD_SUCCESS -eq 0 ]; then
    echo "所有构建都失败了！"
    exit 1
else
    echo "构建完成！成功 $BUILD_SUCCESS/2"
    echo ""
    echo "输出文件："
    [ -f lxdweb-amd64 ] && echo "   - lxdweb-amd64 (x86_64)"
    [ -f lxdweb-arm64 ] && echo "   - lxdweb-arm64 (aarch64)"
fi

