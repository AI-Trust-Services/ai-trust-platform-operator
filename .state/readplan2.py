import json
d=json.load(open(r"C:\Users\D058099\AppData\Local\Temp\claude\C--claude-projects-eu-ai-trust-platform\3e6f074c-e7b9-4f06-8a74-673f3056f4df\tasks\woyg0gpju.output"))
p=d["result"]["plan"]
for k in ["recommendation","controlPoint","durableChange","trialable","rollback","pitfalls"]:
    print("\n## %s\n%s" % (k, p.get(k)))
