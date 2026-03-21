# 测试报告

## 概览

| 项目 | 内容 |
|------|------|
| 测试日期 | 2026-03-21 |
| 被测模块 | smoketest-security-fix-6（Node.js HTTP Counter App） |
| 测试框架 | Docker Smoke Test（curl HTTP 验证）+ npm test（占位符） |
| 总用例数 | 6 |
| 通过 | 6 |
| 失败 | 0 |
| 跳过 | 0 |
| 代码覆盖率 | N/A（无正式测试框架，smoke test 模式） |

---

## 测试环境

- **镜像**：`qa-test-smoketest-security-fix-6`（基于 `node:20-alpine`，多阶段构建，非 root `node` 用户）
- **容器名**：`qa-counter-test`
- **端口映射**：`3000:3000`
- **容器健康状态**：`Up (healthy)`
- **注意**：测试环境存在 `http_proxy` 代理环境变量（`http://127.0.0.1:33210`），所有 curl 请求使用 `--noproxy "*"` 绕过代理直连容器。

---

## 通过的测试

### PASS 1：npm test 占位符

```
命令：docker run --rm qa-test-smoketest-security-fix-6 sh -c "npm test"
输出：
  > smoketest-security-fix-6@1.0.0 test
  > echo 'tests placeholder' && exit 0
  tests placeholder
```

### PASS 2：GET / — 主页 HTML 响应

```
命令：curl -s --noproxy "*" -w "\nHTTP_STATUS:%{http_code}" http://localhost:3000/
输出：
  HTTP Status: 200
  Body: <html><body><h1>Counter App</h1>...</body></html>
结论：200 响应，Body 包含 "Counter App" HTML 内容
```

### PASS 3：GET /count — 初始计数为 0

```
命令：curl -s --noproxy "*" -w "\nHTTP_STATUS:%{http_code}" http://localhost:3000/count
输出：
  HTTP Status: 200
  Body: {"count":0}
结论：200 响应，JSON 格式，初始 count=0
```

### PASS 4：GET /increment — 计数递增

```
命令：curl -s --noproxy "*" -w "\nHTTP_STATUS:%{http_code}" http://localhost:3000/increment
输出：
  HTTP Status: 200
  Body: {"count":1}
结论：200 响应，count 从 0 递增至 1
```

### PASS 5：多次 /increment — 累加验证

```
命令（共 4 次 increment）：
  curl -s --noproxy "*" http://localhost:3000/increment  # count=2
  curl -s --noproxy "*" http://localhost:3000/increment  # count=3
  curl -s --noproxy "*" http://localhost:3000/increment  # count=4（含状态码检查）
  curl -s --noproxy "*" http://localhost:3000/count      # 一致性验证
输出：
  第 4 次 increment → {"count":4}
  /count 端点 → {"count":4}
结论：count 持续累加，/count 与 /increment 状态一致
```

### PASS 6：未知路径 — 回退主页 HTML

```
命令：curl -s --noproxy "*" -w "\nHTTP_STATUS:%{http_code}" http://localhost:3000/unknown-path
输出：
  HTTP Status: 200
  Body: <html><body><h1>Counter App</h1>...</body></html>
结论：未匹配路径回退至主页 HTML，符合源码 else 分支设计
```

---

## 失败的测试

无。所有测试用例全部通过。

---

## 容器日志

```
docker logs qa-counter-test
输出：
  Server running on port 3000
```

日志正常，无异常错误输出。

---

## 覆盖率分析

项目未配置正式测试框架（`package.json` 中 test script 为占位符 `echo 'tests placeholder' && exit 0`），因此无法生成代码覆盖率报告。

根据 smoke test 覆盖情况：

| 代码路径 | 覆盖状态 |
|---------|---------|
| `/increment` 分支 | ✅ 已覆盖 |
| `/count` 分支 | ✅ 已覆盖 |
| `else`（默认主页）分支 | ✅ 已覆盖 |

**建议补充的测试**：
1. 引入 Jest 或 Mocha 等正式测试框架，替换占位符 test script
2. 添加并发请求测试（多个请求同时 `/increment`，验证计数一致性）
3. 测试 PORT 环境变量自定义端口号功能
4. 测试服务器异常关闭/重启后 count 重置的预期行为
5. 测试 Content-Type 响应头是否正确（`application/json` vs `text/html`）

---

## 结论与建议

- **整体质量**：被测应用 `smoketest-security-fix-6` 核心功能全部正常，3 个 HTTP 端点均按预期响应，计数器状态一致。
- **安全修复验证**：应用基于 `node:20-alpine` 多阶段构建，以非 root 用户（`node`）运行，具备健康检查，基础安全配置符合最佳实践。
- **发布建议**：从 smoke test 角度，应用可以发布。但强烈建议在后续迭代中引入正式测试框架，以实现代码级别的单元/集成测试覆盖。
