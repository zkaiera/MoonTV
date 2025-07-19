#!/bin/bash

set -e

echo "🔍 开始检测代码变更..."

# 检测6小时内的变更
SINCE_TIME=$(date -d "6 hours ago" --iso-8601)
echo "🕐 检测时间范围: $SINCE_TIME 至今"
echo "🌍 当前时区: $(date '+%Z %z')"

# 调试：显示最近的所有提交（包括合并提交）
echo "🔍 最近10个提交（包括合并）:"
git log -10 --oneline --pretty=format:"%h %s (%an, %ad)" --date=iso

# 调试：显示最近的非合并提交
echo "🔍 最近10个非合并提交:"
git log -10 --oneline --no-merges --pretty=format:"%h %s (%an, %ad)" --date=iso

# 调试：显示6小时内的所有提交（包括合并）
echo "🔍 6小时内的所有提交（包括合并）:"
git log --since="$SINCE_TIME" --oneline --pretty=format:"%h %s (%an, %ad)" --date=iso

# 获取6小时内的所有提交（包括合并提交和PR）
NEW_COMMITS=$(git log --since="$SINCE_TIME" --oneline \
  --pretty=format:"%h|%s|%an|%ad" --date=short)

# 修复COMMIT_COUNT计算，确保是纯数字
if [ -z "$NEW_COMMITS" ]; then
  COMMIT_COUNT=0
else
  COMMIT_COUNT=$(echo "$NEW_COMMITS" | wc -l)
fi

echo "📊 6小时内发现 $COMMIT_COUNT 个提交"

# 调试：如果没有找到提交，尝试不同的时间范围
if [ "$COMMIT_COUNT" -eq 0 ]; then
  echo "🔍 扩大搜索范围到24小时:"
  RECENT_COMMITS=$(git log --since="24 hours ago" --oneline --no-merges \
    --pretty=format:"%h %s (%an, %ad)" --date=iso | head -5)
  echo "$RECENT_COMMITS"
fi

# 判断执行策略
if [ "$COMMIT_COUNT" -gt 0 ]; then
  # 有6小时内的变更，使用真实数据
  MODE="real"
  DATA_SOURCE="6小时内真实变更"
  COMMITS_DATA="$NEW_COMMITS"
  echo "✅ 使用6小时内真实变更数据"
elif [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ]; then
  # 手动执行且无6小时内变更，使用最近10次提交作为测试
  MODE="test"
  DATA_SOURCE="最近10次提交（测试数据）"
  COMMITS_DATA=$(git log -10 --oneline \
    --pretty=format:"%h|%s|%an|%ad" --date=short)
  COMMIT_COUNT=10
  echo "🧪 使用最近10次提交作为测试数据（包括合并提交）"
else
  # 自动执行且无变更，直接退出
  echo "ℹ️ 未检测到新的代码变更，跳过通知"
  exit 0
fi

# 获取详细变更统计
if [ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ] && [ "$COMMIT_COUNT" -eq 10 ]; then
  # 测试模式：获取最近10次提交的统计
  DETAILED_STATS=$(git log -10 --no-merges --stat \
    --pretty=format:"COMMIT:%h %s")
  FILES_CHANGED=$(git diff --name-only HEAD~10 HEAD 2>/dev/null || echo "")
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

# 计算文件变更数量
FILES_COUNT=$(echo "$FILES_CHANGED" | wc -l)
if [ -z "$FILES_CHANGED" ]; then
  FILES_COUNT=0
fi

# 构建AI提示词
AI_PROMPT="请分析MoonTV项目的代码变更并生成用户友好的更新说明。

## 项目背景
MoonTV是一个基于Next.js 14的现代化影视聚合播放器：
- 技术栈：Next.js 14 + TypeScript + Tailwind CSS
- 主要功能：影视聚合搜索、在线播放、数据同步
- 部署平台：Vercel、Docker、Cloudflare

## 本次变更信息
- 数据来源：${DATA_SOURCE}
- 提交数量：${COMMIT_COUNT}个
- 变更文件：${FILES_COUNT}个

## 提交记录
${FORMATTED_COMMITS}

## 文件变更统计
${DETAILED_STATS}

## 输出要求
请严格按照以下JSON格式输出分析结果，不要包含任何其他内容：

{
  \"details\": [
    \"变更1的详细技术说明\",
    \"变更2的详细技术说明\"
  ],
  \"user_impact\": [
    \"对用户的具体影响1\",
    \"对用户的具体影响2\"
  ],
  \"summary\": \"整体变更的简要总结\"
}

注意事项：
- 使用中文回复
- details：每个重要变更一条，说明技术改进
- user_impact：每个用户可感知的改善一条
- summary：2-3句话的总体描述
- 避免过于技术化的术语
- 输出必须是有效的JSON格式"

# 调用AI API（如果配置了）
if [ -n "$AI_API_KEY" ]; then
  echo "🔑 使用AI API进行分析..."

  AI_API_ENDPOINT="${AI_API_ENDPOINT:-https://api.openai.com/v1/chat/completions}"
  AI_MODEL="${AI_MODEL:-gpt-3.5-turbo}"

  # 调试：显示提示词长度
  echo "🔍 AI提示词长度: $(echo "$AI_PROMPT" | wc -c) 字符"

  # 构建API请求 - 针对Gemini 2.5 Pro thinking优化
  API_REQUEST=$(jq -n \
    --arg model "$AI_MODEL" \
    --arg prompt "$AI_PROMPT" \
    '{
      model: $model,
      messages: [
        {
          role: "system",
          content: "你是一个专业的软件更新分析师，擅长将技术变更转换为用户友好的说明。请仔细分析提供的代码变更信息，生成详细且准确的JSON格式分析结果。"
        },
        {
          role: "user",
          content: $prompt
        }
      ],
      max_tokens: 20000,
      temperature: 0.3
    }')

  # 调试：检查API请求是否构建成功
  if [ $? -eq 0 ]; then
    echo "✅ API请求构建成功"
  else
    echo "❌ API请求构建失败"
    exit 1
  fi

  # 调用AI API
  AI_RESPONSE=$(curl -s -X POST "$AI_API_ENDPOINT" \
    -H "Authorization: Bearer $AI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$API_REQUEST")

  # 调试：显示API响应
  echo "🔍 AI API完整响应:"
  echo "$AI_RESPONSE"
  echo "📏 响应长度: $(echo "$AI_RESPONSE" | wc -c) 字符"

  # 解析AI响应
  AI_CONTENT=$(echo "$AI_RESPONSE" | \
    jq -r '.choices[0].message.content' 2>/dev/null || echo "")

  # 提取JSON部分（去除markdown代码块）
  if [[ "$AI_CONTENT" == *'```json'* ]]; then
    AI_JSON=$(echo "$AI_CONTENT" | sed -n '/```json/,/```/p' | sed '1d;$d')
  else
    AI_JSON="$AI_CONTENT"
  fi

  # 检查finish_reason
  FINISH_REASON=$(echo "$AI_RESPONSE" | jq -r '.choices[0].finish_reason' 2>/dev/null || echo "")
  echo "🔍 AI完成原因: $FINISH_REASON"

  if [ -n "$AI_CONTENT" ] && [ "$AI_CONTENT" != "null" ] && [ "$AI_CONTENT" != "" ]; then
    echo "✅ AI分析成功"
    echo "📝 AI响应长度: $(echo "$AI_CONTENT" | wc -c) 字符"
    echo "🤖 AI解析后的内容:"
    echo "$AI_CONTENT"
  else
    echo "❌ AI分析失败，内容为空"
    echo "完整API响应: $AI_RESPONSE"

    # 检查是否有错误信息
    ERROR_MSG=$(echo "$AI_RESPONSE" | jq -r '.error.message' 2>/dev/null || echo "")
    if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
      echo "API错误信息: $ERROR_MSG"
    fi

    # 检查是否是因为长度限制
    if [ "$FINISH_REASON" = "length" ]; then
      echo "⚠️ 响应因长度限制被截断，但内容为空，可能是模型配置问题"
    fi

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
if [ -n "$AI_JSON" ] && [ "$AI_JSON" != "null" ] && [ "$AI_JSON" != "" ]; then
  AI_DETAILS=$(echo "$AI_JSON" | jq -r '.details[]' 2>/dev/null | \
    sed 's/^/• /' || echo "• AI分析结果解析失败")
  AI_USER_IMPACT=$(echo "$AI_JSON" | jq -r '.user_impact[]' 2>/dev/null | \
    sed 's/^/• /' || echo "• 用户影响分析失败")
  AI_SUMMARY=$(echo "$AI_JSON" | jq -r '.summary' 2>/dev/null || \
    echo "AI总结生成失败")
else
  AI_DETAILS="• AI分析数据不可用"
  AI_USER_IMPACT="• 用户影响分析不可用"
  AI_SUMMARY="AI分析结果不可用，请查看具体提交记录了解更新内容。"
fi

# 构建通知消息
CURRENT_TIME=$(date '+%Y/%m/%d %H:%M:%S')

# 导出变量供envsubst使用
export SITE_NAME CUSTOM_DOMAIN CURRENT_TIME DATA_SOURCE COMMIT_COUNT COMMITS_LIST AI_DETAILS AI_USER_IMPACT AI_SUMMARY

# 调试：显示关键变量
echo "🔍 关键变量检查:"
echo "SITE_NAME: $SITE_NAME"
echo "CURRENT_TIME: $CURRENT_TIME"
echo "DATA_SOURCE: $DATA_SOURCE"
echo "COMMIT_COUNT: $COMMIT_COUNT"
echo "AI_DETAILS长度: $(echo "$AI_DETAILS" | wc -c)"
echo "AI_SUMMARY长度: $(echo "$AI_SUMMARY" | wc -c)"

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
━━━━━━━━━━━━━━━
🤖 AI分析  变更详情🔧
${AI_DETAILS}
━━━━━━━━━━━━━━━
🤖 AI分析 : 用户影响👥
${AI_USER_IMPACT}
━━━━━━━━━━━━━━━
🤖 AI分析 : 总结📝
${AI_SUMMARY}
EOFMSG

# 替换变量
MESSAGE=$(envsubst < /tmp/message.txt)

# 调试：显示最终构建的消息
echo "📝 最终构建的通知消息:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$MESSAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 发送到Webhook
if [ -n "$WECHAT_WEBHOOK_URL" ]; then
  echo "🌐 发送通知到Webhook..."

  # 构建企业微信专用的JSON payload
  PAYLOAD=$(jq -n --arg text "$MESSAGE" '{
    msgtype: "text",
    text: {
      content: $text
    }
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
    echo "📋 企业微信API响应: $(cat /tmp/webhook_response.txt)"
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