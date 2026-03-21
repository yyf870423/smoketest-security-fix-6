# 安全审计报告

## 审计概要

| 项目 | 值 |
|------|-----|
| 项目名称 | smoketest-security-fix-6 |
| 审计时间 | 2026-03-21 |
| 代码库版本 | `7b23b03` |
| 技术栈 | Node.js 20 / 原生 http 模块 / 无外部依赖 / Docker (alpine) |
| 审计范围 | `src/index.js`、`package.json`、`Dockerfile`、`docker-compose.yml`、`.github/workflows/*.yml` |
| 审计工具 | npm audit（ENOLOCK — 无 lockfile，无法运行）、手动代码审查、grep 敏感信息扫描 |

---

## 风险总览

| 级别 | 数量 |
|------|------|
| Critical | 0 |
| High | 0 |
| Medium | 4 |
| Low | 2 |

无 Critical / High 级别发现。应用为纯内存计数器，无数据库、无认证机制、无敏感数据处理，攻击面极小。

---

## 详细发现

### [M-001] `/increment` 端点缺少速率限制

- **级别**：Medium
- **类别**：OWASP A04 — 不安全的设计（Insecure Design）
- **位置**：`src/index.js:4-7`
- **问题描述**：`/increment` 端点对每次请求无条件执行 `count++` 并返回当前值，服务器端未实施任何速率限制。攻击者可在短时间内发送海量请求，造成两类风险：① 计数器被恶意快速刷高，破坏业务数据完整性；② 大量 HTTP 连接消耗服务器 CPU，形成拒绝服务（DoS）压力。
- **证据**：
  ```javascript
  // src/index.js:4-7
  if (req.url === '/increment') {
    count++;
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({count}));
  }
  ```
  代码中无任何 IP 限制、令牌桶、滑动窗口等速率控制逻辑。`docker-compose.yml` 的资源限制（0.5 CPU / 128MB）可缓解极端情况，但无法防止业务层面的计数器滥用。
- **影响**：攻击者可无限制地操纵计数器数值；在无容器资源限制的部署环境下可导致服务不可用。
- **修复建议**：在请求处理逻辑中增加简单的 IP 级速率限制，例如使用滑动窗口记录每个 IP 的请求频率：
  ```javascript
  const rateLimitMap = new Map(); // IP -> { count, windowStart }
  const RATE_LIMIT = 60;          // 每分钟最多 60 次
  const WINDOW_MS = 60 * 1000;

  function isRateLimited(ip) {
    const now = Date.now();
    const record = rateLimitMap.get(ip) || { count: 0, windowStart: now };
    if (now - record.windowStart > WINDOW_MS) {
      record.count = 0;
      record.windowStart = now;
    }
    record.count++;
    rateLimitMap.set(ip, record);
    return record.count > RATE_LIMIT;
  }

  // 在 /increment 处理前调用：
  const clientIp = req.socket.remoteAddress;
  if (isRateLimited(clientIp)) {
    res.writeHead(429, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ error: 'Too Many Requests' }));
    return;
  }
  ```

---

### [M-002] 缺少 HTTP 安全响应头

- **级别**：Medium
- **类别**：OWASP A05 — 安全配置错误（Security Misconfiguration）
- **位置**：`src/index.js:6`、`src/index.js:9`、`src/index.js:12`
- **问题描述**：所有响应（JSON 和 HTML）均未设置任何安全相关的 HTTP 响应头。缺失的关键安全头包括：
  - `Content-Security-Policy`（CSP）
  - `X-Content-Type-Options`
  - `X-Frame-Options`
  - `Strict-Transport-Security`（HSTS，部署于 HTTPS 时）
  - `Referrer-Policy`
- **证据**：
  ```javascript
  // src/index.js:6 — JSON 响应
  res.writeHead(200, {'Content-Type': 'application/json'});

  // src/index.js:12 — HTML 响应（仅设置 Content-Type）
  res.writeHead(200, {'Content-Type': 'text/html'});
  ```
  任何安全扫描工具（如 Mozilla Observatory、securityheaders.com）对该服务器的检测评级将为 F。
- **影响**：
  - 缺少 `X-Frame-Options` → 页面可被嵌入 `<iframe>`，存在点击劫持（Clickjacking）风险
  - 缺少 `X-Content-Type-Options: nosniff` → 浏览器可能对响应进行 MIME 类型嗅探
  - 缺少 CSP → 若将来引入动态内容，XSS 防御缺失
- **修复建议**：创建统一的安全头设置函数，在每个响应中调用：
  ```javascript
  function setSecurityHeaders(res) {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'unsafe-inline'");
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Cache-Control', 'no-store');
  }
  ```

---

### [M-003] 缺少安全事件日志记录

- **级别**：Medium
- **类别**：OWASP A09 — 安全日志记录和监控失败（Security Logging and Monitoring Failures）
- **位置**：`src/index.js:17`（唯一的 console.log 语句）
- **问题描述**：整个应用仅在启动时输出一条日志 `Server running on port <PORT>`。服务运行期间没有任何请求日志、错误日志或异常访问记录。如果服务发生异常（如被攻击、计数器被异常刷高），运营人员无法通过日志进行事后分析。
- **证据**：
  ```javascript
  // src/index.js:17 — 全文仅此一行 console.log
  server.listen(PORT, () => console.log('Server running on port ' + PORT));
  ```
  代码中无 `req.method`、`req.url`、响应状态码、客户端 IP 的记录逻辑。
- **影响**：无法检测异常流量模式；发生安全事件时无法溯源；违反基本的可观测性要求。
- **修复建议**：在请求处理入口处增加最小日志记录：
  ```javascript
  const server = http.createServer((req, res) => {
    const start = Date.now();
    res.on('finish', () => {
      const duration = Date.now() - start;
      console.log(JSON.stringify({
        ts: new Date().toISOString(),
        method: req.method,
        url: req.url,
        status: res.statusCode,
        ip: req.socket.remoteAddress,
        ms: duration
      }));
    });
    // ... 原有路由逻辑
  });
  ```

---

### [M-004] 未定义路由统一返回 HTTP 200

- **级别**：Medium
- **类别**：OWASP A05 — 安全配置错误（Security Misconfiguration）
- **位置**：`src/index.js:11-14`
- **问题描述**：路由逻辑使用 `else` 分支兜底，将所有非 `/increment` 和 `/count` 的请求（包括 `/admin`、`/api/v1/secret`、`/../etc/passwd` 等任意路径）均返回 HTTP 200 及 HTML 计数器页面。正确行为应为返回 HTTP 404。此问题导致：① 安全扫描工具无法通过 HTTP 状态码区分有效路径和无效路径；② 可能掩盖配置错误（如上游代理将请求路由到错误路径）。
- **证据**：
  ```javascript
  // src/index.js:11-14
  } else {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<html><body>...</body></html>');
  }
  ```
  验证：向 `/nonexistent`、`/admin`、`/.env` 等路径发送请求，均会收到 HTTP 200。
- **影响**：安全扫描器无法识别无效路径；混淆监控告警；HTTP 200 的 "catch-all" 行为违反 REST 语义约定。
- **修复建议**：将 `else` 分支拆分，仅对根路径 `/` 返回 HTML，其余未知路径返回 404：
  ```javascript
  } else if (req.url === '/' || req.url === '') {
    res.writeHead(200, {'Content-Type': 'text/html'});
    res.end('<html>...</html>');
  } else {
    res.writeHead(404, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ error: 'Not Found' }));
  }
  ```

---

### [L-001] 缺少 package-lock.json 锁文件

- **级别**：Low
- **类别**：OWASP A08 — 软件和数据完整性失败（Software and Data Integrity Failures）
- **位置**：项目根目录（`package.json` 存在，`package-lock.json` 不存在）
- **问题描述**：`package.json` 中未锁定任何外部依赖（目前无依赖），因此尚无实际安全风险。但缺少 lockfile 意味着一旦未来添加外部依赖，`npm install` 将自动安装满足语义化版本约束的最新版本，可能引入含 CVE 的版本。此外，CI 流水线中使用了 `npm ci`（`.github/workflows/ci.yml:48,49`），该命令要求 `package-lock.json` 存在，否则构建失败。
- **证据**：
  ```bash
  # npm audit 执行结果
  {
    "error": {
      "code": "ENOLOCK",
      "summary": "This command requires an existing lockfile.",
      "detail": "Try creating one first with: npm i --package-lock-only"
    }
  }

  # CI 工作流
  # .github/workflows/ci.yml:48
  npm ci   # 需要 package-lock.json，但文件不存在
  ```
- **影响**：当前无直接安全风险（无外部依赖）；CI pipeline 在有依赖时会失败；未来添加依赖后面临供应链攻击风险。
- **修复建议**：立即生成并提交锁文件：
  ```bash
  npm install --package-lock-only
  git add package-lock.json
  git commit -m "chore: add package-lock.json"
  ```

---

### [L-002] 所有端点无访问控制

- **级别**：Low
- **类别**：OWASP A01 — 访问控制失效（Broken Access Control）
- **位置**：`src/index.js:4-14`
- **问题描述**：`/increment` 和 `/count` 端点完全公开，任何人无需认证即可访问和操作。对于当前的"公共计数器"业务场景，这可能是有意为之的设计。标记为 Low 是为提示：若业务需求发生变化（如需要防止未授权用户操纵计数器），则需补充认证机制。
- **证据**：
  ```javascript
  // src/index.js:4-7 — 无中间件、无 token 校验、无 IP 白名单
  if (req.url === '/increment') {
    count++;
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({count}));
  }
  ```
- **影响**：任何互联网用户均可无限制地递增计数器；若业务要求计数器真实反映某种受控操作，此设计不满足需求。
- **修复建议**：
  - 若为公共计数器（当前设计意图）：无需修改，但应结合 M-001 的速率限制防止滥用。
  - 若需要受控访问：为 `/increment` 添加简单的 API Key 验证，通过 `Authorization` 请求头传递。

---

## OWASP Top 10（2021）覆盖汇总

| 编号 | 类别 | 发现 | 备注 |
|------|------|------|------|
| A01 | 访问控制失效 | L-002 | 无认证，设计上可能有意为之 |
| A02 | 加密失败 | 无 | 无敏感数据处理，无密码存储 |
| A03 | 注入攻击 | 无 | 无数据库、无 eval/exec、无动态 HTML 渲染 |
| A04 | 不安全的设计 | M-001 | `/increment` 无速率限制 |
| A05 | 安全配置错误 | M-002, M-004 | 缺安全头、全路径返回 200 |
| A06 | 易受攻击的组件 | 无 | 零外部依赖，npm audit 无法运行（无 lockfile）|
| A07 | 认证和会话管理失败 | 无 | 应用无认证设计，无会话机制 |
| A08 | 软件和数据完整性失败 | L-001 | 缺少 package-lock.json |
| A09 | 安全日志记录和监控失败 | M-003 | 无请求日志 |
| A10 | SSRF | 无 | 无用户可控的外部 URL 请求 |

---

## 总结与建议

### 总体安全评估

该应用为极简的单文件 Node.js HTTP 服务，代码量仅 17 行，无数据库、无认证、无敏感数据处理，整体攻击面非常小。**未发现 Critical 或 High 级别安全漏洞**。主要问题集中在防御纵深不足（安全头缺失、无速率限制）和可观测性缺失（无日志）。

### 优先修复顺序

1. **M-001（速率限制）** — 防止计数器被恶意刷高和资源耗尽，实现成本低，收益明显
2. **M-002（安全响应头）** — 一次性添加，保护将来功能扩展时的安全基线
3. **M-003（请求日志）** — 提升可观测性，对生产运营至关重要
4. **M-004（正确 HTTP 状态码）** — 小改动，改善语义正确性
5. **L-001（锁文件）** — `npm install --package-lock-only` 一行命令解决

### 长期安全改进建议

- **依赖管理**：即使当前无外部依赖，也应建立 lockfile 提交规范，并在 CI 中配置 `npm audit --audit-level=high` 作为门禁
- **基础设施安全**：部署时应在 Nginx/反向代理层统一配置 HTTPS 和安全头，作为第二道防线
- **监控告警**：建议接入集中式日志系统（如 ELK、Loki），设置异常请求频率告警
- **容器安全**：Dockerfile 已采用非 root 用户（`USER node`）和最小镜像（alpine），安全实践良好，无需改动
