# 魔方财务-LXD 对接插件 (zjmf-lxd-server)

这是一个为 [魔方财务](https://www.zjmf.com/) (ZJMF) 系统开发的 LXD 对接插件，为主机商提供完整的 LXD 容器销售与管理解决方案。

## 📖 文档

**详细的安装和使用文档，请参考 [项目 Wiki](https://github.com/xkatld/zjmf-lxd-server/wiki)。**

## 🚀 项目特色

- **高性能后端**: 使用 Go 语言开发的独立后端服务，支持多架构部署
- **完整功能**: 容器创建、管理、监控、流量统计、VNC 控制台等
- **安全可靠**: API 认证、HTTPS 加密、权限控制
- **易于集成**: 与魔方财务系统无缝对接，支持自动化销售流程

## 新版本计划

肝炸了慢慢更新中，希望在使用的朋友发现bug及时反馈。

- 添加nginx反代理功能
- 适配mysql数据库
- 开发管理后端web

## 🏗️ 项目结构

```
├── lxd-api-go/          # Go 后端服务
└── lxdserver/           # PHP 前端插件
```

## 项目截图

<img width="1627" height="822" alt="image" src="https://github.com/user-attachments/assets/3ebffd81-2d6a-4ef5-b514-c59db4e0d32d" />
<img width="1624" height="819" alt="image" src="https://github.com/user-attachments/assets/3ec609da-e8c7-4a34-afcd-15329bf8880a" />
<img width="1243" height="902" alt="image" src="https://github.com/user-attachments/assets/f28f8354-6143-498e-a170-05d2b585c873" />
<img width="742" height="375" alt="image" src="https://github.com/user-attachments/assets/0c2fd90e-8c53-478b-9849-e38f1c621721" />
<img width="1639" height="828" alt="image" src="https://github.com/user-attachments/assets/d36dcdc0-0fe8-4310-b39f-920c9c9dce6c" />
