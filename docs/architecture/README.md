# Architecture diagrams

| File | What it shows | Use it for |
|---|---|---|
| [`architecture.png`](architecture.png) | Every component: VPCs, subnets, gateways, endpoints, security and monitoring | README, report, first slide |
| [`traffic-flows.png`](traffic-flows.png) | 10 numbered flows (who → through what → to what, on which port) and the paths blocked on purpose | Explaining the design, demo walkthrough |

Both are **diagrams as code**: hand-laid SVG with the official AWS Architecture Icons and AWS group
colours (VPC purple, public subnet green, private subnet teal, security red). Positions are fixed in
the scripts, so the layout does not change when you regenerate.

```bash
cd docs/architecture
pip install playwright && playwright install chromium   # once
python3 architecture.py && python3 traffic_flows.py
python3 render.py architecture traffic-flows            # writes the PNGs (2x)
```

`architecture.svg` and `traffic-flows.svg` open in any browser or in draw.io (File > Import) if
you want to edit by hand. Icons in `icons/` come from the AWS Architecture Icons set.

Other design docs here: [`cidr-plan.md`](cidr-plan.md), [`route-tables.md`](route-tables.md).
