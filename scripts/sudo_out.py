"""sudo 跑远端命令并打印输出：密码经 SOPS 取、只走 stdin，不进 argv、不打印。用法: sudo_out.py <host,host> <remote cmd>
（tp8_up.sh 用它在八台上关深睡眠态。注意：`spark_sudo` 是部署者自有模块——`_password()` 从你的密管（如 SOPS+age）解出 sudo 密码字符串、`CFG` 是 ssh config 路径；公开仓库不含该模块，请按自己的密管实现。示例用户 deploy / 示例网段均为文档占位。）"""
import asyncio
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "desktop-hand"))
import spark_sudo as S  # noqa: E402

hosts = sys.argv[1].split(",")
remote = sys.argv[2]
pw = asyncio.run(S._password())
for h in hosts:
    cmd = ["ssh", "-F", S.CFG, "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", h, f"sudo -S -p '' {remote}"]
    try:
        p = subprocess.run(cmd, input=pw + "\n", text=True, capture_output=True, timeout=40,
                           encoding="utf-8", errors="replace")
        print(f"===== {h} rc={p.returncode}")
        print(p.stdout.rstrip())
        if p.stderr.strip():
            print("[stderr]", p.stderr.strip()[-300:])
    except subprocess.TimeoutExpired:
        print(f"===== {h} timeout")
