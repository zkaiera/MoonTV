#!/bin/bash

set -e

echo "🔍 开始检测代码变更..."

# 检测6小时内的变更
SINCE_TIME=$(date -d "6 hours ago" --iso-8601)
NEW_COMMITS=$(git log --since="$SINCE_TIME" --oneline --no-merges \
  --pretty=format:"%h|%s|%an|%ad" --date=short)
COMMIT_COUNT=$(echo "$NEW_COMMITS" | grep -c . || echo "0")

echo "📊 6小时内发现 $COMMIT_COUNT 个提交"

# 判断执行策略
if [ "$COMMIT_COUNT" -gt 0 ]; then
  # 有6小时内的变更，使用真实数据
  MODE="real"
  DATA_SOURCE="6小时内真实变更"
  COMMITS_DATA="$NEW_COMMITS"
  echo "✅ 使用6小时内真实变更数据"
elif [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then
  # 手动执行且无6小时内变更，使用最近5次提交作为测试
  MODE="test"
  DATA_SOURCE="最近5次提交（测试数据）"
  COMMITS_DATA=$(git log -5 --oneline --no-merges \
    --pretty=format:"%h|%s|%an|%ad" --date=short)
  COMMIT_COUNT=5
  echo "🧪 使用最近5次提交作为测试数据"
else
  # 自动执行且无变更，直接退出
  echo "ℹ️ 未检测到新的代码变更，跳过通知"
  exit 0
fi

# 获取详细变更统计
if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ] && [ "$COMMIT_COUNT" -eq 5 ]; then
  # 测试模式：获取最近5次提交的统计
  DETAILED_STATS=$(git log -5 --no-merges --stat \
    --pretty=format:"COMMIT:%h %s")
  FILES_CHANGED=$(git diff --name-only HEAD~5 HEAD 2>/dev/null || echo "")
else
  # 真实模式：获取6小时内的统计
  DETAILED_STATS=$(git log --since="$SINCE_TIME" --no-merges --stat \
    --pretty=format:"COMMIT:%h %s")
  FILES_CHANGED=$(git diff --name-only HEAD~$COMMIT_COUNT HEAD \
    2>/dev/null || echo "")
fi

echo "🔍 变更检测完成: 分析 $COMMIT_COUNT 个提交"

# 开始AI分析
echo "🤖 开始AI分析..."

# 格式化提交列表
FORMATTED_COMMITS=""
while IFS='|' read -r hash message author date; do
  if [ -n "$hash" ]; then
    FORMATTED_COMMITS="${FORMATTED_COMMITS}- ${hash}: ${message} (${author}, ${date})\n"
  fi
done <<< "$COMMITS_DATA"

# 构建AI提示词
AI_PROMPT="你是MoonTV项目的技术更新分析专家。MoonTV是一个基于Next.js 14的现代化影视聚合播放器，支持多源搜索、在线播放、收藏同步等功能。

项目背景：
- 项目名称：MoonTV
- 技术栈：Next.js 14 + TypeScript + Tailwind CSS
- 主要功能：影视聚合搜索、在线播放、数据同步
- 部署平台：Vercel、Docker、Cloudflare

本次变更概览：
- 数据来源：${DATA_SOURCE}
- 提交数量：${COMMIT_COUNT}个
- 变更文件：$(echo "$FILES_CHANGED" | wc -l)个

详细提交记录：
$(echo -e "$FORMATTED_COMMITS")

文件变更统计：
$DETAILED_STATS

请按以下JSON格式输出分析结果：
{
  \"details\": [
    \"针对每个重要变更的详细说明，突出技术改进点\",
    \"另一个变更的详细说明\"
  ],
  \"user_impact\": [
    \"对用户体验的具体影响1\",
    \"对用户体验的具体影响2\"
  ],
  \"summary\": \"将所有变更整合为2-3句话的总体描述\"
}

要求：
1. 使用中文回复，语言简洁专业
2. details数组：每个重要变更一条，说明技术改进
3. user_impact数组：每个用户可感知的改善一条
4. summary：整体总结，突出本次更新的核心价值
5. 避免过于技术化的术语，普通用户能理解
6. 如果是依赖更新，重点说明安全性或性能提升
7. 如果是UI/功能改进，说明具体的用户体验提升"

# 调用AI API（如果配置了）
if [ -n "$AI_API_KEY" ]; then
  echo "🔑 使用AI API进行分析..."

  AI_API_ENDPOINT="${AI_API_ENDPOINT:-https://api.openai.com/v1/chat/completions}"
  AI_MODEL="${AI_MODEL:-gpt-3.5-turbo}"

  # 构建API请求
  API_REQUEST=$(jq -n \
    --arg model "$AI_MODEL" \
    --arg prompt "$AI_PROMPT" \
    '{
      model: $model,
      messages: [
        {
          role: "system",
          content: "你是一个专业的软件更新分析师，擅长将技术变更转换为用户友好的说明。"
        },
        {
          role: "user",
          content: $prompt
        }
      ],
      max_tokens: 800,
      temperature: 0.7
    }')

  # 调用AI API
  AI_RESPONSE=$(curl -s -X POST "$AI_API_ENDPOINT" \
    -H "Authorization: Bearer $AI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$API_REQUEST")

  # 解析AI响应
  AI_CONTENT=$(echo "$AI_RESPONSE" | \
    jq -r '.choices[0].message.content' 2>/dev/null || echo "")

  if [ -n "$AI_CONTENT" ] && [ "$AI_CONTENT" != "null" ]; then
    echo "✅ AI分析成功"
  else
    echo "❌ AI分析失败，API响应异常"
    exit 1
  fi
else
  echo "⚠️ 未配置AI_API_KEY，跳过AI分析"
  exit 1
fi

# 发送通知
echo "📤 开始构建并发送通知..."

# 设置站点信息
SITE_NAME="${SITE_NAME:-MoonTV}"
CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-您的域名}"

# 格式化提交列表
COMMITS_LIST=""
while IFS='|' read -r hash message author date; do
  if [ -n "$hash" ]; then
    COMMITS_LIST="${COMMITS_LIST}• ${hash} ${message}\n"
  fi
done <<< "$COMMITS_DATA"

# 解析AI分析结果
if [ -n "$AI_CONTENT" ] && [ "$AI_CONTENT" != "null" ]; then
  AI_DETAILS=$(echo "$AI_CONTENT" | jq -r '.details[]' 2>/dev/null | \
    sed 's/^/• /' | tr '\n' '\n' || echo "• AI分析结果解析失败")
  AI_USER_IMPACT=$(echo "$AI_CONTENT" | jq -r '.user_impact[]' 2>/dev/null | \
    sed 's/^/• /' | tr '\n' '\n' || echo "• 用户影响分析失败")
  AI_SUMMARY=$(echo "$AI_CONTENT" | jq -r '.summary' 2>/dev/null || \
    echo "AI总结生成失败")
else
  AI_DETAILS="• AI分析数据不可用"
  AI_USER_IMPACT="• 用户影响分析不可用"
  AI_SUMMARY="AI分析结果不可用，请查看具体提交记录了解更新内容。"
fi

# 构建通知消息
CURRENT_TIME=$(date '+%Y/%m/%d %H:%M:%S')

cat > /tmp/message.txt << 'EOFMSG'
🚀 ${SITE_NAME} 更新通知

📅 检查时间: ${CURRENT_TIME}
✅ 检查结果: 脚本运行成功
🔄 更新状态: 检测到更新并已同步
📊 数据来源: ${DATA_SOURCE}

🚀 Vercel将为您自动部署
🌐 访问 ${CUSTOM_DOMAIN} 查看最新版本

━━━━━━━━━━━━━━━
📊 本次分析 ${COMMIT_COUNT} 个提交

📋 变更概览:
${COMMITS_LIST}
━━━━━━━━━━━━━━━
🤖 AI智能分析:

🔧 变更详情
${AI_DETAILS}

👥 用户影响
${AI_USER_IMPACT}

📝 总结
${AI_SUMMARY}
EOFMSG

# 替换变量
MESSAGE=$(envsubst < /tmp/message.txt)

# 发送到Webhook
if [ -n "$WECHAT_WEBHOOK_URL" ]; then
  echo "🌐 发送通知到Webhook..."

  # 构建通用的JSON payload
  PAYLOAD=$(jq -n --arg text "$MESSAGE" '{
    text: $text,
    content: $text
  }')

  # 发送请求
  HTTP_STATUS=$(curl -s -o /tmp/webhook_response.txt \
    -w "%{http_code}" \
    -X POST "$WECHAT_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    --max-time 30 \
    --retry 2 \
    --retry-delay 3)

  if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    echo "✅ 通知发送成功 (HTTP $HTTP_STATUS)"
  else
    echo "❌ 通知发送失败 (HTTP $HTTP_STATUS)"
    echo "响应内容: $(cat /tmp/webhook_response.txt)"
    exit 1
  fi
else
  echo "⚠️ 未配置WECHAT_WEBHOOK_URL，跳过通知发送"
  exit 1
fi

echo "✅ 成功分析 $COMMIT_COUNT 个提交并发送通知"
echo "📊 数据来源: $DATA_SOURCE"
echo "🤖 AI分析: 已完成"
echo "📤 通知发送: 已完成" 