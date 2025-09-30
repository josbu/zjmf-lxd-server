#!/bin/bash

# 简单的交叉编译脚本

echo "开始交叉编译 lxdimages..."

# 清理旧文件
rm -f lxdimages-*

# 编译 Linux amd64
echo "编译 Linux amd64..."
GOOS=linux GOARCH=amd64 go build -o lxdimages-amd64 .

# 编译 Linux arm64  
echo "编译 Linux arm64..."
GOOS=linux GOARCH=arm64 go build -o lxdimages-arm64 .

echo "编译完成！"
ls -la lxdimages-*