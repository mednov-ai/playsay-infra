from pathlib import Path
import re
play=(Path(__file__).resolve().parents[1]/"ansible/playbooks/ax41-dev-html-game-library.yaml").read_text()
pattern=re.search(r"game_route_pattern: '([^']+)'",play)[1]
replacement=re.search(r"game_route_replacement: '([^']+)'",play)[1]
old=r"location ~ ^/api/(?:materials/[^/]+/assets/html-games|schedule/lessons/[^/]+/html-game-page)$ {"
def block(host): return "server {\n    server_name "+host+";\n    "+old+"\n        client_max_body_size 21m;\n    }\n}\n"
prod=block("online.honey.school")
dev=block("dev.online.honey.school")
source=prod+dev+block("key.honey.school")
result=re.sub(pattern,replacement,source)
assert result.startswith(prod)
assert result.endswith(block("key.honey.school"))
assert result.count("games(?:/")==1
assert re.sub(pattern,replacement,result)==result
assert re.sub(pattern,replacement,prod)==prod
print("DEV-only route replacement preserves production and is idempotent")
