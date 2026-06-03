#!/usr/bin/env bash
# Tokei Collector — 远程设备一键部署
# 用法: curl -sL <url>/install.sh | bash -s -- --repo <git-repo-url> --name <device-name>
set -e

REPO=""
NAME=""
INTERVAL=5
SCRIPT_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo) REPO="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

if [ -z "$REPO" ]; then
    echo "用法: install.sh --repo <git-repo-url> --name <device-name>"
    echo "  --repo      同步 Git 仓库地址(必填)"
    echo "  --name      设备名(默认: hostname)"
    echo "  --interval  同步间隔分钟(默认: 5)"
    exit 1
fi

[ -z "$NAME" ] && NAME=$(hostname -s)

echo "=== Tokei Collector 安装 ==="
echo "  仓库: $REPO"
echo "  设备: $NAME"
echo "  间隔: ${INTERVAL}m"
echo ""

# 1. 创建目录
TOKEI_DIR="$HOME/.tokei"
SYNC_DIR="$TOKEI_DIR/sync"
mkdir -p "$TOKEI_DIR"

# 2. 克隆同步仓库
if [ -d "$SYNC_DIR/.git" ]; then
    echo "[✓] 同步仓库已存在"
    cd "$SYNC_DIR" && git pull -q
else
    echo "[·] 克隆同步仓库..."
    git clone "$REPO" "$SYNC_DIR"
fi

# 3. 下载采集脚本(如果不在本地)
SCRIPT="$TOKEI_DIR/usage.30s.py"
if [ -f "$SCRIPT" ]; then
    echo "[✓] 采集脚本已存在"
else
    # 尝试从同步仓库获取,或从当前目录复制
    if [ -f "$(dirname "$0")/usage.30s.py" ]; then
        cp "$(dirname "$0")/usage.30s.py" "$SCRIPT"
    elif [ -f "$SYNC_DIR/usage.30s.py" ]; then
        cp "$SYNC_DIR/usage.30s.py" "$SCRIPT"
    else
        echo "[!] 请手动复制 usage.30s.py 到 $SCRIPT"
        echo "    scp your-mac:path/to/usage.30s.py $SCRIPT"
    fi
fi

# 4. 写配置
cat > "$TOKEI_DIR/config.json" <<EOF
{
  "sync_dir": "$SYNC_DIR",
  "device_id": "$NAME"
}
EOF
echo "[✓] 配置已写入 $TOKEI_DIR/config.json"

# 5. 创建同步脚本
SYNC_SCRIPT="$TOKEI_DIR/sync.sh"
cat > "$SYNC_SCRIPT" <<'SYNCEOF'
#!/usr/bin/env bash
cd "$HOME/.tokei/sync" || exit 1
python3 "$HOME/.tokei/usage.30s.py" --json >/dev/null 2>&1
git pull -q --rebase --autostash 2>/dev/null
git add -A
git diff --cached --quiet || git commit -qm "tokei sync $(cat $HOME/.tokei/config.json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("device_id","unknown"))' 2>/dev/null || echo unknown)"
git push -q 2>/dev/null
SYNCEOF
chmod +x "$SYNC_SCRIPT"
echo "[✓] 同步脚本: $SYNC_SCRIPT"

# 6. 添加 crontab
CRON_LINE="*/$INTERVAL * * * * $SYNC_SCRIPT >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -v "tokei/sync.sh"; echo "$CRON_LINE") | crontab -
echo "[✓] Cron 已配置: 每 ${INTERVAL} 分钟同步"

echo ""
echo "=== 安装完成 ==="
echo "  首次同步: bash $SYNC_SCRIPT"
echo "  查看状态: cat $SYNC_DIR/$NAME.json | python3 -m json.tool | head -5"
echo ""

# 7. 立即执行一次
bash "$SYNC_SCRIPT" && echo "[✓] 首次同步成功" || echo "[!] 首次同步失败,请检查 Git 权限"
