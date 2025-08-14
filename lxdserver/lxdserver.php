<?php

use app\common\logic\RunMap;
use app\common\model\HostModel;
use think\Db;

// 调试模式配置 - 手动修改此值来控制调试输出
define('LXDSERVER_DEBUG', true); // true=调试模式, false=生产模式

// 调试日志函数
function lxdserver_debug($message, $data = null) {
    if (!LXDSERVER_DEBUG) return;

    $log = '[LXD-DEBUG] ' . $message;
    if ($data !== null) {
        $log .= ' | Data: ' . json_encode($data, JSON_UNESCAPED_UNICODE);
    }
    error_log($log);
}

// 插件元数据
function lxdserver_MetaData()
{
    return [
        'DisplayName' => '魔方财务-LXD对接插件 by xkatld',
        'APIVersion'  => '1.0.1',
        'HelpDoc'     => 'https://github.com/xkatld/zjmf-lxd-server',
    ];
}

// 产品配置选项
function lxdserver_ConfigOptions()
{
    return [
        [
            'type'        => 'text',
            'name'        => '核心',
            'description' => 'CPU核心数',
            'default'     => '1',
            'key'         => 'cpus',
        ],
        [
            'type'        => 'text',
            'name'        => '内存',
            'description' => 'MB',
            'default'     => '512',
            'key'         => 'memory',
        ],
        [
            'type'        => 'text',
            'name'        => '硬盘',
            'description' => 'GB',
            'default'     => '10',
            'key'         => 'disk',
        ],
        [
            'type'        => 'text',
            'name'        => '上行带宽',
            'description' => 'Mbps',
            'default'     => '100',
            'key'         => 'ingress',
        ],
        [
            'type'        => 'text',
            'name'        => '下行带宽',
            'description' => 'Mbps',
            'default'     => '100',
            'key'         => 'egress',
        ],
        [
            'type'        => 'text',
            'name'        => '镜像',
            'description' => '容器镜像名称',
            'default'     => 'ubuntu24',
            'key'         => 'image',
        ],
        [
            'type'        => 'dropdown',
            'name'        => '是否开启嵌套',
            'description' => '允许容器内运行虚拟化',
            'default'     => 'true',
            'key'         => 'allow_nesting',
            'options'     => [
                'true'  => '启用',
                'false' => '禁用',
            ],
        ],
        [
            'type'        => 'text',
            'name'        => 'NAT规则数量限制',
            'description' => '单个容器允许的最大NAT转发规则数量（不包括SSH端口）',
            'default'     => '5',
            'key'         => 'nat_limit',
        ],
    ];
}

// 测试API连接
function lxdserver_TestLink($params)
{
    lxdserver_debug('开始测试API连接', $params);

    $data = [
        'url'  => '/api/check',
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];

    $res = lxdserver_Curl($params, $data, 'GET');
    lxdserver_debug('API连接测试响应', $res);

    if ($res === null) {
        return [
            'status' => 200,
            'data'   => [
                'server_status' => 0,
                'msg'           => "无法连接到LXD API服务器，请检查服务器IP、端口或确认API服务是否正在运行。",
            ],
        ];
    }

    if (isset($res['code'])) {
        if ($res['code'] == 200 && isset($res['msg']) && $res['msg'] == 'API连接正常') {
            $lxdVersion = $res['data']['lxd_version'] ?? 'unknown';
            $apiVersion = $res['data']['api_version'] ?? '1.0.0';
            return [
                'status' => 200,
                'data'   => [
                    'server_status' => 1,
                    'msg'           => "LXD API服务器连接成功且API密钥有效。(LXD版本: {$lxdVersion}, API版本: {$apiVersion})",
                ],
            ];
        }

        if ($res['code'] == 401) {
            return [
                'status' => 200,
                'data'   => [
                    'server_status' => 0,
                    'msg'           => "LXD API服务器连接成功，但提供的API密钥无效。",
                ],
            ];
        }

        return [
            'status' => 200,
            'data'   => [
                'server_status' => 0,
                'msg'           => "LXD API服务器连接成功，但API响应了非预期的状态。Code: " . $res['code'],
            ],
        ];
    }

    return [
        'status' => 200,
        'data'   => [
            'server_status' => 0,
            'msg'           => "连接到LXD API服务器但收到意外的响应格式。",
        ],
    ];
}

// 客户区域面板配置
function lxdserver_ClientArea($params)
{
    return [
        'info'    => ['name' => '产品信息'],
        'nat_acl' => ['name' => 'NAT转发'],
    ];
}

// 客户区域输出处理
function lxdserver_ClientAreaOutput($params, $key)
{
    lxdserver_debug('ClientAreaOutput调用', ['key' => $key, 'action' => $_GET['action'] ?? null]);

    // 处理API请求
    if (isset($_GET['action'])) {
        $action = $_GET['action'];
        lxdserver_debug('处理API请求', ['action' => $action, 'domain' => $params['domain'] ?? null]);

        if (empty($params['domain'])) {
            header('Content-Type: application/json');
            echo json_encode(['code' => 400, 'msg' => '容器域名未设置']);
            exit;
        }

        // API端点映射
        $apiEndpoints = [
            'getinfo'    => '/api/status',
            'getstats'   => '/api/info',
            'gettraffic' => '/api/traffic',
            'getinfoall' => '/api/info',
            'natlist'    => '/api/natlist',
        ];

        $apiEndpoint = $apiEndpoints[$action] ?? '';

        if (!$apiEndpoint) {
            header('Content-Type: application/json');
            echo json_encode(['code' => 400, 'msg' => '不支持的操作: ' . $action]);
            exit;
        }

        $requestData = [
            'url'  => $apiEndpoint . '?hostname=' . $params['domain'],
            'type' => 'application/x-www-form-urlencoded',
            'data' => [],
        ];

        lxdserver_debug('发送API请求', $requestData);
        $res = lxdserver_Curl($params, $requestData, 'GET');
        lxdserver_debug('API响应', $res);

        // 处理响应
        if ($res === null) {
            $res = ['code' => 500, 'msg' => '连接服务器失败'];
        } elseif (!is_array($res)) {
            $res = ['code' => 500, 'msg' => '服务器返回了无效的响应格式'];
        } else {
            $res = lxdserver_TransformAPIResponse($action, $res);
        }

        // 返回JSON响应
        header('Content-Type: application/json');
        header('Cache-Control: no-cache, no-store, must-revalidate');
        header('Pragma: no-cache');
        header('Expires: 0');
        echo json_encode($res);
        exit;
    }

    // 返回模板
    if ($key == 'info') {
        return [
            'template' => 'templates/info.html',
            'vars'     => [],
        ];
    }

    if ($key == 'nat_acl') {
        $requestData = [
            'url'  => '/api/natlist?hostname=' . $params['domain'] . '&_t=' . time(),
            'type' => 'application/x-www-form-urlencoded',
            'data' => [],
        ];
        $res = lxdserver_Curl($params, $requestData, 'GET');

        // 计算当前NAT规则数量和限制
        $nat_limit = intval($params['configoptions']['nat_limit'] ?? 5);
        $current_count = lxdserver_getNATRuleCount($params);

        return [
            'template' => 'templates/nat.html',
            'vars'     => [
                'list' => $res['data'] ?? [],
                'msg'  => $res['msg'] ?? '',
                'nat_limit' => $nat_limit,
                'current_count' => $current_count,
                'remaining_count' => max(0, $nat_limit - $current_count),
            ],
        ];
    }
}

// 允许的客户端函数
function lxdserver_AllowFunction()
{
    return [
        'client' => ['natadd', 'natdel', 'natlist'],
    ];
}

// 创建容器账户
function lxdserver_CreateAccount($params)
{
    lxdserver_debug('开始创建容器', ['domain' => $params['domain']]);

    $sys_pwd = $params['password'] ?? randStr(8);

    $data = [
        'url'  => '/api/create',
        'type' => 'application/json',
        'data' => [
            'hostname'      => $params['domain'],
            'password'      => $sys_pwd,
            'cpus'          => (int)($params['configoptions']['cpus'] ?? 1),
            'memory'        => (int)($params['configoptions']['memory'] ?? 512),
            'disk'          => (int)($params['configoptions']['disk'] ?? 10),
            'image'         => $params['configoptions']['image'] ?? 'ubuntu24',
            'ingress'       => (int)($params['configoptions']['ingress'] ?? 100),
            'egress'        => (int)($params['configoptions']['egress'] ?? 100),
            'allow_nesting' => ($params['configoptions']['allow_nesting'] ?? 'false') === 'true',
        ],
    ];

    lxdserver_debug('发送创建请求', $data);
    $res = lxdserver_JSONCurl($params, $data, 'POST');
    lxdserver_debug('创建响应', $res);

    if (isset($res['code']) && $res['code'] == '200') {
        // 快速创建成功，直接更新数据库
        $update = [
            'dedicatedip'  => $params['server_ip'],
            'domainstatus' => 'Active',
            'username'     => $params['domain'],
        ];

        // 从响应中获取SSH端口
        if (!empty($res['data']['ssh_port'])) {
            $update['port'] = $res['data']['ssh_port'];
            lxdserver_debug('获取到SSH端口', ['ssh_port' => $res['data']['ssh_port']]);
        } else {
            lxdserver_debug('警告：响应中没有SSH端口信息', $res);
        }

        try {
            Db::name('host')->where('id', $params['hostid'])->update($update);
            lxdserver_debug('数据库更新成功', $update);
        } catch (\Exception $e) {
             return ['status' => 'error', 'msg' => ($res['msg'] ?? '创建成功，但同步数据到面板失败: ' . $e->getMessage())];
        }

        return ['status' => 'success', 'msg' => $res['msg'] ?? '创建成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? '创建失败'];
    }
}

// 同步容器状态
function lxdserver_Sync($params)
{
    $data = [
        'url'  => '/api/status?hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    if (isset($res['code']) && $res['code'] == '200') {
        if (class_exists('think\Db') && isset($params['hostid'])) {
            try {
                Db::name('host')->where('id', $params['hostid'])->update([
                    'dedicatedip' => $params['server_ip'],
                ]);
            } catch (Exception $e) {
                lxdserver_debug('同步数据库失败', ['error' => $e->getMessage()]);
            }
        }
        return ['status' => 'success', 'msg' => $res['msg'] ?? '同步成功'];
    }

    return ['status' => 'error', 'msg' => $res['msg'] ?? '同步失败'];
}

// 删除容器
function lxdserver_TerminateAccount($params)
{
    $data = [
        'url'  => '/api/delete?hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    return isset($res['code']) && $res['code'] == '200'
        ? ['status' => 'success', 'msg' => $res['msg'] ?? '删除成功']
        : ['status' => 'error', 'msg' => $res['msg'] ?? '删除失败'];
}

// 开机容器
function lxdserver_On($params)
{
    $data = [
        'url'  => '/api/boot?hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    return isset($res['code']) && $res['code'] == '200'
        ? ['status' => 'success', 'msg' => $res['msg'] ?? '开机成功']
        : ['status' => 'error', 'msg' => $res['msg'] ?? '开机失败'];
}

function lxdserver_Off($params)
{
    $data = [
        'url'  => '/api/stop?' . 'hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    if (isset($res['code']) && $res['code'] == '200') {
        return ['status' => 'success', 'msg' => $res['msg'] ?? '关机成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? '关机失败'];
    }
}

function lxdserver_Reboot($params)
{
    $data = [
        'url'  => '/api/reboot?' . 'hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    if (isset($res['code']) && $res['code'] == '200') {
        return ['status' => 'success', 'msg' => $res['msg'] ?? '重启成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? '重启失败'];
    }
}

// 获取容器当前NAT规则数量
function lxdserver_getNATRuleCount($params)
{
    $data = [
        'url'  => '/api/natlist?hostname=' . urlencode($params['domain']),
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];

    $res = lxdserver_Curl($params, $data, 'GET');

    if (isset($res['code']) && $res['code'] == 200 && isset($res['data']) && is_array($res['data'])) {
        // 直接返回NAT规则总数（不包括SSH端口，因为SSH端口不在NAT规则列表中）
        return count($res['data']);
    }

    return 0; // 如果获取失败，返回0（允许添加）
}

function lxdserver_natadd($params)
{
    parse_str(file_get_contents("php://input"), $post);

    $dport = intval($post['dport'] ?? 0);
    $sport = intval($post['sport'] ?? 0);
    $dtype = strtolower(trim($post['dtype'] ?? ''));

    if (!($dtype == "tcp" || $dtype == "udp")) {
        return ['status' => 'error', 'msg' => '未知映射类型'];
    }
    if ($sport <= 0 || $sport > 65535) {
        return ['status' => 'error', 'msg' => '容器内部端口超过范围'];
    }

    // 检查NAT规则数量限制
    $nat_limit = intval($params['configoptions']['nat_limit'] ?? 5);

    // 获取当前容器的NAT规则数量（不包括SSH端口）
    $current_count = lxdserver_getNATRuleCount($params);
    if ($current_count >= $nat_limit) {
        return ['status' => 'error', 'msg' => "NAT规则数量已达到限制（{$nat_limit}条），无法添加更多规则"];
    }

    // 强制由后端自动分配外网端口：不再接受前端传入的 dport
    $requestData = 'hostname=' . urlencode($params['domain']) . '&dtype=' . urlencode($dtype) . '&sport=' . $sport;

    $data = [
        'url'  => '/api/addport',
        'type' => 'application/x-www-form-urlencoded',
        'data' => $requestData,
    ];

    $res = lxdserver_Curl($params, $data, 'POST');

    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => $res['msg'] ?? 'NAT转发添加成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? 'NAT转发添加失败'];
    }
}

function lxdserver_natdel($params)
{
    parse_str(file_get_contents("php://input"), $post);

    $dport = intval($post['dport'] ?? 0);
    $sport = intval($post['sport'] ?? 0);
    $dtype = strtolower(trim($post['dtype'] ?? ''));

    if (!($dtype == "tcp" || $dtype == "udp")) {
        return ['status' => 'error', 'msg' => '未知映射类型'];
    }
    if ($sport <= 0 || $sport > 65535) {
        return ['status' => 'error', 'msg' => '容器内部端口超过范围'];
    }
    if ($dport < 10000 || $dport > 65535) {
        return ['status' => 'error', 'msg' => '外网端口映射范围为10000-65535'];
    }

    $data = [
        'url'  => '/api/delport',
        'type' => 'application/x-www-form-urlencoded',
        'data' => 'hostname=' . urlencode($params['domain']) . '&dtype=' . urlencode($dtype) . '&dport=' . $dport . '&sport=' . $sport,
    ];

    $res = lxdserver_Curl($params, $data, 'POST');

    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => $res['msg'] ?? 'NAT转发删除成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? 'NAT转发删除失败'];
    }
}

function lxdserver_Status($params)
{
    $data = [
        'url'  => '/api/status?' . 'hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    if (isset($res['code']) && $res['code'] == 200) {
        $result = ['status' => 'success'];

        // 获取容器状态
        $containerStatus = $res['data']['status'] ?? '';

        // 状态映射
        switch (strtoupper($containerStatus)) {
            case 'RUNNING':
                $result['data']['status'] = 'on';
                $result['data']['des'] = '开机';
                break;
            case 'STOPPED':
                $result['data']['status'] = 'off';
                $result['data']['des'] = '关机';
                break;
            case 'FROZEN':
                $result['data']['status'] = 'suspend';
                $result['data']['des'] = '暂停';
                break;
            default:
                $result['data']['status'] = 'unknown';
                $result['data']['des'] = '未知状态';
                break;
        }

        return $result;
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? '获取状态失败'];
    }
}

function lxdserver_CrackPassword($params, $new_pass)
{
    $data = [
        'url'  => '/api/password',
        'type' => 'application/json',
        'data' => [
            'hostname' => $params['domain'],
            'password' => $new_pass,
        ],
    ];
    $res = lxdserver_JSONCurl($params, $data, 'POST');

    if (isset($res['code']) && $res['code'] == 200) {
        try {
            Db::name('host')->where('id', $params['hostid'])->update(['password' => $new_pass]);
        } catch (\Exception $e) {
            return ['status' => 'error', 'msg' => ($res['msg'] ?? $res['message'] ?? 'LXD容器密码重置成功，但同步新密码到面板数据库失败: ' . $e->getMessage())];
        }
        return ['status' => 'success', 'msg' => $res['msg'] ?? $res['message'] ?? '密码重置成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? $res['message'] ?? '密码重置失败'];
    }
}

function lxdserver_Reinstall($params)
{
    if (empty($params['reinstall_os'])) {
        return ['status' => 'error', 'msg' => '操作系统参数错误'];
    }

    $reinstall_pass = $params['password'] ?? randStr(8);

    $data = [
        'url'  => '/api/reinstall',
        'type' => 'application/json',
        'data' => [
            'hostname' => $params['domain'],
            'system'   => $params['reinstall_os'],
            'password' => $reinstall_pass,
        ],
    ];
    $res = lxdserver_JSONCurl($params, $data, 'POST');

    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => $res['msg'] ?? $res['message'] ?? '重装成功'];
    } else {
        return ['status' => 'error', 'msg' => $res['msg'] ?? $res['message'] ?? '重装失败'];
    }
}

function lxdserver_JSONCurl($params, $data = [], $request = 'POST')
{
    $curl = curl_init();

    // 默认使用HTTPS协议（TLS已启用）
    $isSecure = true;

    // 检查secure参数，如果明确设置为禁用则使用HTTP
    if (isset($params['secure'])) {
        $secureValue = strtolower(trim($params['secure']));
        $isSecure = !in_array($secureValue, ['off', '0', 'false', 'no', 'disabled']);
    }

    $protocol = $isSecure ? 'https' : 'http';
    $url = $protocol . '://' . $params['server_ip'] . ':' . $params['port'] . $data['url'];

    $curlOptions = [
        CURLOPT_URL            => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_ENCODING       => '',
        CURLOPT_MAXREDIRS      => 10,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_1_1,
        CURLOPT_CUSTOMREQUEST  => $request,
        CURLOPT_POSTFIELDS     => json_encode($data['data']),
        CURLOPT_HTTPHEADER     => [
            'apikey: ' . $params['accesshash'],
            'Content-Type: application/json',
        ],
    ];

    // 如果使用HTTPS，添加SSL选项
    if ($isSecure) {
        $curlOptions[CURLOPT_SSL_VERIFYPEER] = false;
        $curlOptions[CURLOPT_SSL_VERIFYHOST] = false;
    }

    curl_setopt_array($curl, $curlOptions);

    $response = curl_exec($curl);
    $errno    = curl_errno($curl);

    curl_close($curl);

    if ($errno) {
        return null;
    }

    return json_decode($response, true);
}

function lxdserver_Curl($params, $data = [], $request = 'POST')
{
    $curl = curl_init();

    // 默认使用HTTPS协议（TLS已启用）
    $isSecure = true;

    // 检查secure参数，如果明确设置为禁用则使用HTTP
    if (isset($params['secure'])) {
        $secureValue = strtolower(trim($params['secure']));
        $isSecure = !in_array($secureValue, ['off', '0', 'false', 'no', 'disabled']);
    }

    $protocol = $isSecure ? 'https' : 'http';
    $url = $protocol . '://' . $params['server_ip'] . ':' . $params['port'] . $data['url'];

    lxdserver_debug('发送请求', [
        'url' => $url,
        'method' => $request,
        'secure' => $isSecure
    ]);

    $postFields = ($request === 'POST' || $request === 'PUT') ? ($data['data'] ?? null) : null;
    if ($request === 'GET' && !empty($data['data']) && is_array($data['data'])) {
        $url .= (strpos($url, '?') === false ? '?' : '&') . http_build_query($data['data']);
    } elseif ($request === 'GET' && !empty($data['data']) && is_string($data['data'])) {
         $url .= (strpos($url, '?') === false ? '?' : '&') . $data['data'];
    }

    $curlOptions = [
        CURLOPT_URL            => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_ENCODING       => '',
        CURLOPT_MAXREDIRS      => 10,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_1_1,
        CURLOPT_CUSTOMREQUEST  => $request,
        CURLOPT_HTTPHEADER     => [
            'apikey: ' . $params['accesshash'],
            'Content-Type: ' . ($data['type'] ?? 'application/x-www-form-urlencoded'),
        ],
    ];

    // 如果使用HTTPS，添加SSL选项
    if ($isSecure) {
        $curlOptions[CURLOPT_SSL_VERIFYPEER] = false; // 忽略自签证书验证
        $curlOptions[CURLOPT_SSL_VERIFYHOST] = false; // 忽略主机名验证
    }

    curl_setopt_array($curl, $curlOptions);

    if ($postFields !== null) {
        curl_setopt($curl, CURLOPT_POSTFIELDS, $postFields);
    }

    $response = curl_exec($curl);
    $errno    = curl_errno($curl);
    $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);

    curl_close($curl);

    lxdserver_debug('请求响应', [
        'http_code' => $httpCode,
        'response_length' => strlen($response)
    ]);

    if ($errno) {
        lxdserver_debug('CURL错误', ['error' => curl_strerror($errno)]);
        return null;
    }

    $decoded = json_decode($response, true);
    lxdserver_debug('解析响应', ['code' => $decoded['code'] ?? 'NO CODE']);
    return $decoded;
}

// API响应格式转换
function lxdserver_TransformAPIResponse($action, $response)
{
    if (!isset($response['code']) || $response['code'] != 200) {
        return $response; // 错误响应直接返回
    }

    switch ($action) {
        case 'getinfo':
            // 状态查询，已经是正确格式
            return $response;

        case 'getstats':
        case 'getinfoall':
            // 容器信息查询，需要转换格式
            if (isset($response['data'])) {
                $data = $response['data'];

                // 转换为模板期望的格式
                $transformed = [
                    'code' => 200,
                    'msg' => '获取容器信息成功',
                    'data' => [
                        // 基本信息
                        'hostname' => $data['hostname'] ?? '',
                        'status' => $data['status'] ?? '',
                        'ipv4' => $data['ipv4'] ?? '',
                        'ipv6' => $data['ipv6'] ?? '',
                        'type' => $data['type'] ?? '',
                        'created_at' => $data['created_at'] ?? '',

                        // 配置信息
                        'cpus' => $data['config']['cpus'] ?? 1,
                        'memory' => $data['memory'] ?? 1024,  // 使用原始数字
                        'disk' => $data['disk'] ?? 10,        // 使用原始数字

                        // 格式化配置信息（用于前端显示）
                        'config' => [
                            'cpus' => $data['config']['cpus'] ?? 1,
                            'memory' => $data['config']['memory'] ?? '1024 MB',
                            'disk' => $data['config']['disk'] ?? '10 GB',
                        ],

                        // 实时使用情况
                        'cpu_usage' => $data['usage']['cpu_usage'] ?? 0,
                        'memory_usage' => $data['usage']['memory_usage'] ?? '0 B',
                        'memory_usage_raw' => $data['usage']['memory_usage_raw'] ?? 0,
                        'disk_usage' => $data['usage']['disk_usage'] ?? '0 B',
                        'disk_usage_raw' => $data['usage']['disk_usage_raw'] ?? 0,
                        'traffic_usage' => $data['usage']['traffic_usage'] ?? '0 B',
                        'traffic_usage_raw' => $data['usage']['traffic_usage_raw'] ?? 0,

                        // 使用率百分比
                        'cpu_percent' => $data['usage_percent']['cpu_percent'] ?? 0,
                        'memory_percent' => $data['usage_percent']['memory_percent'] ?? 0,
                        'disk_percent' => $data['usage_percent']['disk_percent'] ?? 0,

                        // 添加时间戳用于调试
                        'last_update' => date('Y-m-d H:i:s'),
                        'timestamp' => time(),
                    ]
                ];

                return $transformed;
            }
            break;

        case 'gettraffic':
            if (isset($response['data']['used'])) {
                return [
                    'code' => 200,
                    'msg' => '获取流量使用量成功',
                    'data' => [
                        'used' => $response['data']['used'],
                    ]
                ];
            }
            break;
    }

    return $response; // 默认返回原响应
}

function lxdserver_natlist($params)
{
    $requestData = [
        'url'  => '/api/natlist?' . 'hostname=' . $params['domain'] . '&_t=' . time(),
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $requestData, 'GET');
    if ($res === null) {
        return ['code' => 500, 'msg' => '连接API服务器失败', 'data' => []];
    }
    return $res;
}

// VNC控制台功能
function lxdserver_vnc($params) {
    lxdserver_debug('VNC控制台请求', ['domain' => $params['domain']]);

    // 检查容器状态
    $data = [
        'url'  => '/api/status?hostname=' . $params['domain'],
        'type' => 'application/x-www-form-urlencoded',
        'data' => [],
    ];
    $res = lxdserver_Curl($params, $data, 'GET');

    if (!isset($res['code']) || $res['code'] != '200') {
        return ['status' => 'error', 'msg' => $res['msg'] ?? '无法获取容器状态'];
    }

    if (!isset($res['data']['status']) || $res['data']['status'] !== 'RUNNING') {
        return ['status' => 'error', 'msg' => '容器未运行，无法连接控制台'];
    }

    // 生成控制台令牌
    $tokenData = [
        'url'  => '/api/console/create-token',
        'type' => 'application/json',
        'data' => [
            'hostname' => $params['domain'],
            'user_id' => (int)($params['userid'] ?? 0),
            'service_id' => (int)($params['serviceid'] ?? 0),
            'server_ip' => $params['server_ip'] ?? '',
            'expires_in' => 3600
        ],
    ];

    $tokenRes = lxdserver_JSONCurl($params, $tokenData, 'POST');
    lxdserver_debug('VNC令牌响应', $tokenRes);

    if (!isset($tokenRes['code']) || $tokenRes['code'] != 200) {
        return ['status' => 'error', 'msg' => $tokenRes['msg'] ?? '生成控制台令牌失败'];
    }

    // 构建控制台URL
    $protocol = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on') ? 'https' : 'http';
    $consoleUrl = $protocol . '://' . $params['server_ip'] . ':' . $params['port'] . '/console?token=' . $tokenRes['data']['token'];

    lxdserver_debug('VNC控制台URL生成', ['url' => $consoleUrl]);

    return [
        'status' => 'success',
        'url' => $consoleUrl,
        'msg' => '控制台连接已准备就绪'
    ];
}