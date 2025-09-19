#!/bin/bash

# KRDB 分步发布脚本 - 支持断点续传
# 使用方法: ./publish-to-github-packages.sh <版本号-wedevote> [GroupId] [GitHub用户名] [GitHub Token]

set -e

# 默认值
DEFAULT_GROUP_ID="io.github.xilinjia.krdb"

# 从 gradle.properties 获取默认 GitHub 用户名，和 Github Personal Access Token
DEFAULT_GITHUB_USER=""
if [ -f "$HOME/.gradle/gradle.properties" ]; then
    DEFAULT_GITHUB_USER=$(grep "^gpr.user=" "$HOME/.gradle/gradle.properties" 2>/dev/null | cut -d'=' -f2)
fi

DEFAULT_GITHUB_TOKEN=""
if [ -f "$HOME/.gradle/gradle.properties" ]; then
    DEFAULT_GITHUB_TOKEN=$(grep "^gpr.key=" "$HOME/.gradle/gradle.properties" 2>/dev/null | cut -d'=' -f2)
fi

# 参数解析
VERSION="$1"
GROUP_ID="${2:-$DEFAULT_GROUP_ID}"
GITHUB_USER="${3:-$DEFAULT_GITHUB_USER}"
GITHUB_TOKEN="${4:-$DEFAULT_GITHUB_TOKEN}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 状态文件
STATUS_FILE=".publish-status-${VERSION}.txt"

echo -e "${BLUE}=== KRDB 分步发布脚本 ===${NC}"
echo ""

# 参数验证
if [ -z "$VERSION" ]; then
    echo -e "${RED}错误: 请提供版本号${NC}"
    echo ""
    echo "使用方法: $0 <版本号-wedevote> [GroupId] [GitHub用户名] [GitHub Token]"
    echo ""
    echo "示例:"
    echo "  $0 3.2.8-wedevote"
    echo "  $0 3.2.8-wedevote io.github.xilinjia.krdb"
    exit 1
fi

# 验证版本号后缀
if [[ ! "$VERSION" =~ -wedevote$ ]]; then
    echo -e "${RED}错误: 版本号必须以 '-wedevote' 结尾${NC}"
    echo ""
    echo "当前版本号: $VERSION"
    echo "正确格式: <版本号>-wedevote"
    echo ""
    echo "示例:"
    echo "  ✅ 3.2.8-wedevote"
    echo "  ✅ 1.0.0-wedevote"
    echo "  ❌ 3.2.8"
    echo "  ❌ 3.2.8-beta"
    exit 1
fi

if [ -z "$GITHUB_USER" ]; then
    echo -e "${RED}错误: 未找到 GITHUB_USER${NC}"
    echo ""
    echo "请通过以下方式配置 GitHub User:"
    echo ""
    echo -e "${YELLOW}方式1: gradle.properties${NC}"
    echo "  echo 'gpr.user=your_username' >> ~/.gradle/gradle.properties"
    echo ""
    echo -e "${YELLOW}方式2: 命令行参数${NC}"
    echo "  $0 $VERSION $GROUP_ID your_username"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}错误: 未找到 GITHUB_TOKEN${NC}"
    echo ""
    echo "请通过以下方式配置 GitHub Token:"
    echo ""
    echo -e "${YELLOW}方式1: gradle.properties${NC}"
    echo "  echo 'gpr.key=your_token' >> ~/.gradle/gradle.properties"
    echo ""
    echo -e "${YELLOW}方式2: 命令行参数${NC}"
    echo "  $0 $VERSION $GROUP_ID $GITHUB_USER your_token"
    exit 1
fi

# 显示配置信息
echo -e "${CYAN}发布配置:${NC}"
echo "  📦 版本号: $VERSION"
echo "  🏢 Group ID: $GROUP_ID"
echo "  👤 GitHub 用户: $GITHUB_USER"
echo "  🔑 GitHub Token: ${GITHUB_TOKEN:0:8}..."
echo ""

# 设置环境变量供 Gradle 使用
export GITHUB_ACTOR="$GITHUB_USER"
export GITHUB_TOKEN="$GITHUB_TOKEN"

# 构建项目参数
GRADLE_ARGS="-Drealm.kotlin.version=$VERSION -Drealm.kotlin.group=$GROUP_ID"

# 定义所有需要发布的模块和任务（基于实际的 Gradle 任务）
declare -a PUBLISH_TASKS=(
    "packages:cinterop:publishAndroidReleasePublicationToGitHubPackagesRepository"
    "packages:cinterop:publishIosArm64PublicationToGitHubPackagesRepository"
    "packages:cinterop:publishIosSimulatorArm64PublicationToGitHubPackagesRepository"
    "packages:cinterop:publishIosX64PublicationToGitHubPackagesRepository"
    "packages:cinterop:publishJvmPublicationToGitHubPackagesRepository"
    "packages:cinterop:publishKotlinMultiplatformPublicationToGitHubPackagesRepository"
    "packages:cinterop:publishMacosArm64PublicationToGitHubPackagesRepository"
    "packages:cinterop:publishMacosX64PublicationToGitHubPackagesRepository"
    "packages:library-base:publishAndroidReleasePublicationToGitHubPackagesRepository"
    "packages:library-base:publishIosArm64PublicationToGitHubPackagesRepository"
    "packages:library-base:publishIosSimulatorArm64PublicationToGitHubPackagesRepository"
    "packages:library-base:publishIosX64PublicationToGitHubPackagesRepository"
    "packages:library-base:publishJvmPublicationToGitHubPackagesRepository"
    "packages:library-base:publishKotlinMultiplatformPublicationToGitHubPackagesRepository"
    "packages:library-base:publishMacosArm64PublicationToGitHubPackagesRepository"
    "packages:library-base:publishMacosX64PublicationToGitHubPackagesRepository"
    "packages:plugin-compiler:publishCompilerPluginPublicationToGitHubPackagesRepository"
    "packages:plugin-compiler-shaded:publishCompilerPluginShadedPublicationToGitHubPackagesRepository"
    "packages:gradle-plugin:publishGradlePluginPublicationToGitHubPackagesRepository"
    "packages:jni-swig-stub:publishJniSwigStubsPublicationToGitHubPackagesRepository"
)

# 读取已完成的任务
declare -a COMPLETED_TASKS=()
if [ -f "$STATUS_FILE" ]; then
    echo -e "${YELLOW}发现状态文件，读取已完成的任务...${NC}"
    while IFS= read -r line; do
        COMPLETED_TASKS+=("$line")
    done < "$STATUS_FILE"
    echo "  已完成: ${#COMPLETED_TASKS[@]} 个任务"
    echo ""
fi

# 函数：检查任务是否已完成
is_task_completed() {
    local task="$1"
    for completed in "${COMPLETED_TASKS[@]}"; do
        if [ "$completed" = "$task" ]; then
            return 0
        fi
    done
    return 1
}

# 函数：标记任务为已完成
mark_task_completed() {
    local task="$1"
    echo "$task" >> "$STATUS_FILE"
    COMPLETED_TASKS+=("$task")
}

# 函数：发布单个任务
publish_task() {
    local task="$1"
    local task_num="$2"
    local total_tasks="$3"
    
    echo -e "${CYAN}[$task_num/$total_tasks] 发布: $task${NC}"
    
    if is_task_completed "$task"; then
        echo -e "${GREEN}  ✅ 已完成，跳过${NC}"
        return 0
    fi
    
    if ./gradlew "$task" $GRADLE_ARGS --no-daemon; then
        echo -e "${GREEN}  ✅ 成功${NC}"
        mark_task_completed "$task"
        return 0
    else
        echo -e "${RED}  ❌ 失败${NC}"
        echo ""
        echo -e "${YELLOW}任务失败: $task${NC}"
        echo ""
        echo -e "${BLUE}解决方案:${NC}"
        echo "1. 如果是 409 冲突错误，请手动删除 GitHub Packages 中对应的不完整包"
        echo "2. 删除后重新运行此脚本，它会从失败的地方继续"
        echo "3. 已成功的任务不会重复执行"
        echo ""
        echo -e "${CYAN}重新运行命令:${NC}"
        echo "  $0 $VERSION $GROUP_ID $GITHUB_USER"
        echo ""
        exit 1
    fi
}

# 确认发布
echo -e "${YELLOW}准备发布 ${#PUBLISH_TASKS[@]} 个发布任务${NC}"
if [ ${#COMPLETED_TASKS[@]} -gt 0 ]; then
    echo -e "${GREEN}其中 ${#COMPLETED_TASKS[@]} 个任务已完成${NC}"
fi
echo ""
echo -e "${YELLOW}是否继续? (y/N)${NC}"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "取消发布"
    exit 0
fi

echo ""
echo -e "${BLUE}开始分步发布...${NC}"
echo ""

# 执行发布
TOTAL_TASKS=${#PUBLISH_TASKS[@]}
CURRENT_TASK=1

for task in "${PUBLISH_TASKS[@]}"; do
    publish_task "$task" "$CURRENT_TASK" "$TOTAL_TASKS"
    CURRENT_TASK=$((CURRENT_TASK + 1))
    
    # 添加短暂延迟，避免 GitHub API 限制
    if [ $CURRENT_TASK -le $TOTAL_TASKS ]; then
        echo "  等待 2 秒..."
        sleep 2
        echo ""
    fi
done

echo ""
echo -e "${GREEN}🎉 所有任务发布成功!${NC}"
echo ""
echo -e "${BLUE}发布信息:${NC}"
echo "  📦 包名: $GROUP_ID"
echo "  🏷️  版本: $VERSION"
echo "  📍 仓库: https://github.com/WeDevote/krdb/packages"
echo ""
echo -e "${CYAN}清理状态文件...${NC}"
rm -f "$STATUS_FILE"
echo "完成!"
