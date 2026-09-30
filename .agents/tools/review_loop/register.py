import sys
import os
import subprocess

target = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "tools", "review_loop", "register.py"))
if os.path.exists(target) and target != os.path.abspath(__file__):
    result = subprocess.run([sys.executable, target] + sys.argv[1:], capture_output=False)
    sys.exit(result.returncode)
else:
    sys.exit(0)
