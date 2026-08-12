import json
d=json.load(open(r"C:\Users\D058099\AppData\Local\Temp\claude\C--claude-projects-eu-ai-trust-platform\3e6f074c-e7b9-4f06-8a74-673f3056f4df\tasks\wfflu1cti.output"))
r=d["result"]; p=r["plan"]
print("=== PLAN ===")
for k in ["recommendation","feasible","stagedPlan","rollback","pitfalls"]:
    print("\n## %s\n%s" % (k, p.get(k)))
print("\n=== Task C (pitfalls/labels) ===")
for c in r["inv"]:
    if "labelCount" in c:
        print("labelCount:", c.get("labelCount"))
        print("pitfalls:", c.get("pitfalls"))
        print("rollback:", c.get("rollback"))
print("\n=== backup ===")
b=r["backup"]; print("saved:",b.get("saved"),"| files:",b.get("files"),"| restore:",b.get("restoreCmd"))
