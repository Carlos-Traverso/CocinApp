#!/usr/bin/env python3
"""Render backend_schema.json as a high-resolution, self-contained UML poster."""
from __future__ import annotations
import html, json, math, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent
SOURCE = ROOT / "backend_schema.json"
SVG = ROOT / "cocinapp_backend_uml.svg"
PREVIEW = ROOT / "cocinapp_backend_uml_preview.svg"
W = 3000
PAD, GAP, COLS = 64, 32, 4
CW = (W - PAD * 2 - GAP * (COLS - 1)) // COLS
LINE, HEAD, FOOT = 38, 38, 22
CARD_START = 570
BG, INK, MUTED = "#f4f7fb", "#16283d", "#587087"
ACCENTS = ["#236c9b", "#087e78", "#6e5aab", "#b36b22", "#39794d", "#a54860"]

def esc(x): return html.escape(str(x), quote=True)
def group(name):
    n=name.lower()
    if any(k in n for k in ("recipe", "receta", "ingredient", "ingrediente", "category", "categoria", "unit", "unidad", "dietary", "dietetica", "tag")): return "Recetas y catálogo"
    if any(k in n for k in ("shopping", "compra", "planes_comida", "plan_comida")): return "Planificación y compras"
    if any(k in n for k in ("pantry", "despensa", "receipt", "ticket")): return "Despensa y comprobantes"
    if any(k in n for k in ("cooking", "coccion", "cocina", "event")): return "Cocción y actividad"
    if any(k in n for k in ("user", "usuario", "profile", "perfil", "account", "personal", "auth", "admin")): return "Usuarios y administración"
    return "Sistema y configuración"
def tkey(schema,name): return f"{schema}.{name}"
def solo_unique_columns(t):
    import re
    result=set()
    for con in t.get("constraints",[]):
        if con.get("type","").lower()=="unique" and len(con.get("columns",[]))==1:
            result.add(con["columns"][0])
    for ix in t.get("unique_indexes",[]):
        m=re.search(r'\(([^()]*)\)',ix.get("definition", ""))
        if ix.get("unique") and not ix.get("predicate") and m:
            cols=[v.strip().strip('"') for v in m.group(1).split(",")]
            if len(cols)==1 and re.fullmatch(r'[a-zA-Z_][a-zA-Z_0-9]*',cols[0]): result.add(cols[0])
    return result

def main():
    data=json.loads(SOURCE.read_text(encoding="utf-8-sig"))
    tables=[dict(t,columns=(t["columns"][:1] if t.get("external") else t["columns"])) for t in data["tables"]]
    fks=data.get("foreign_keys", [])
    fk_map={}
    for i,f in enumerate(fks,1):
        fk_map.setdefault((tkey(f.get("source_schema","public"),f["source_table"]),tuple(f["source_columns"])),[]).append((i,f))
    grouped={}
    for t in tables: grouped.setdefault(group(t["name"]),[]).append(t)
    # Split large semantic groups across the four columns, balancing by exact
    # card height (attributes + composite keys + unique indexes).
    cols=[[] for _ in range(COLS)]; heights=[0]*COLS
    def card_height(t):
        keys=sum(1 for c in t.get("constraints",[]) if c.get("type","").lower() in ("primary_key","unique"))
        return HEAD+22+LINE*len(t["columns"])+FOOT*(keys+len(t.get("unique_indexes",[])))+12
    for g,ts in sorted(grouped.items(), key=lambda kv:-sum(card_height(t) for t in kv[1])):
        per_col=[[] for _ in range(COLS)]
        for t in sorted(ts,key=card_height,reverse=True):
            idx=min(range(COLS),key=lambda i:heights[i]+(HEAD+12 if not per_col[i] else 0))
            per_col[idx].append(t); heights[idx]+=card_height(t)
        for i,items in enumerate(per_col):
            if items:
                cols[i].append((g,items)); heights[i]+=HEAD+24
    maxh=max(heights)
    # Relationship catalogue (source/target + delete behavior) is part of this image.
    cat_rows=max(1,math.ceil(len(fks)/3)); CAT_HEAD=60; CAT_ROW=27
    cat_h=CAT_HEAD+cat_rows*CAT_ROW+108
    H=CARD_START+maxh+cat_h+70
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', '<defs><filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#17324d" flood-opacity=".10"/></filter><marker id="arrow" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto"><path d="M0 0 L7 3.5 L0 7 Z" fill="#49647d"/></marker></defs>',f'<rect width="100%" height="100%" fill="{BG}"/>']
    def txt(x,y,s,size=16,fill=INK,weight=400,anchor="start",family="Segoe UI,Arial,sans-serif"):
        out.append(f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>')
    txt(PAD,70,"CocinAPP · Modelo relacional completo",38,INK,700)
    txt(PAD,108,"Esquema implementado hasta 202611010012 · pendiente de despliegue permanente · 2026-11-01",19,MUTED)
    txt(PAD,151,f'36 tablas de aplicación · 271 atributos · {len(fks)} claves foráneas declaradas · auth.users (id externo)',17,INK,600)
    txt(PAD,181,"Cada tarjeta conserva nombres y tipos del esquema. Las relaciones se enumeran abajo con su FK y acción ON DELETE.",15,MUTED)
    ystarts=[CARD_START]*COLS
    # Precompute table and field positions; FK connector paths route through the
    # clear top band and numbered relationship catalogue to avoid crossing cards.
    positions={}; field_y={}
    for ci,items in enumerate(cols):
        x=PAD+ci*(CW+GAP); y=CARD_START
        for g,ts in items:
            y+=HEAD+12
            for t in ts:
                rows=t["columns"]; cons=t.get("constraints",[])
                keys=[c for c in cons if c.get("type","").lower() in ("primary_key","unique")]
                indexes=t.get("unique_indexes",[])
                extra=FOOT*(len(keys)+len(indexes))
                positions[tkey(t.get("schema","public"),t["name"])]=(x,y,CW,HEAD+22+LINE*len(rows)+extra)
                for ri,col in enumerate(rows): field_y[(tkey(t.get("schema","public"),t["name"]),col["name"])]=y+HEAD+22+ri*LINE+16
                y+=HEAD+22+LINE*len(rows)+extra+12
            y+=12
    # Each database FK has a numbered, directional line glyph, corresponding
    # exactly to its row in the complete relationship catalogue.
    for i,f in enumerate(fks,1):
        src=tkey(f.get("source_schema","public"),f["source_table"]); dst=tkey(f.get("target_schema","public"),f["target_table"])
        sx,sy,sw,sh=positions[src]; dx,dy,dw,dh=positions[dst]
        sy=field_y.get((src,f["source_columns"][0]),sy+sh/2)
        dy=field_y.get((dst,f["target_columns"][0]),dy+dh/2)
        # Separate paths into broad numbered rails across the reserved header band.
        rail=220+(i-1)*5
        color=ACCENTS[(i-1)%len(ACCENTS)]
        if sx==dx:
            startx=sx+sw+2; endx=dx+dw+2; bend=max(startx,endx)+8+(i%5)*5
            path=f'M{startx},{sy} H{bend} V{dy} H{endx}'
        else:
            if sx<dx:
                startx=sx+sw; endx=dx; direction=1
            else:
                startx=sx; endx=dx+dw; direction=-1
            path=f'M{startx},{sy} C{startx+24*direction},{sy} {startx+24*direction},{rail} {startx+48*direction},{rail} H{endx-48*direction} C{endx-24*direction},{rail} {endx-24*direction},{dy} {endx},{dy}'
            # Square-corner SVG overlay is the same numbered relation route and
            # also gives the PNG renderer portable line primitives.
            for x1,y1,x2,y2 in ((startx,sy,startx,rail),(startx,rail,endx,rail),(endx,rail,endx,dy)):
                out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.2" stroke-opacity=".26"/>')
        if sx==dx:
            for x1,y1,x2,y2 in ((startx,sy,bend,sy),(bend,sy,bend,dy),(bend,dy,endx,dy)):
                out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="1.2" stroke-opacity=".26"/>')
        out.append(f'<path d="{path}" fill="none" stroke="{color}" stroke-width="1.4" stroke-opacity=".42" marker-end="url(#arrow)"/>')
    for ci,items in enumerate(cols):
        x=PAD+ci*(CW+GAP); y=ystarts[ci]
        for gi,(g,ts) in enumerate(items):
            color=ACCENTS[(sum(map(ord,g))%len(ACCENTS))]
            out.append(f'<rect x="{x}" y="{y}" width="{CW}" height="{HEAD}" rx="8" fill="{color}"/>')
            txt(x+16,y+25,g,17,"#ffffff",700); y+=HEAD+12
            for t in ts:
                rows=t["columns"]
                key_cons=[c for c in t.get("constraints",[]) if c.get("type","").lower() in ("primary_key","unique")]
                indexes=t.get("unique_indexes",[])
                card_h=HEAD+22+LINE*len(rows)+FOOT*(len(key_cons)+len(indexes))
                out.append(f'<rect x="{x}" y="{y}" width="{CW}" height="{card_h}" rx="8" fill="#ffffff" stroke="#d6e0ea" filter="url(#sh)"/>')
                out.append(f'<path d="M{x+8} {y} H{x+CW-8} Q{x+CW} {y} {x+CW} {y+8} V{y+HEAD} H{x} V{y+8} Q{x} {y} {x+8} {y}" fill="#eaf1f7"/>')
                txt(x+14,y+24,"«table»",12,color,600)
                txt(x+CW-14,y+24,("auth." if t.get("external") else "")+t["name"],17,INK,700,"end")
                for ri,c in enumerate(rows):
                    cy=y+HEAD+22+ri*LINE
                    tags=[]
                    if c.get("primary_key"): tags.append("PK")
                    if c["name"] in solo_unique_columns(t) and not c.get("primary_key"): tags.append("UQ")
                    matches=fk_map.get((tkey(t.get("schema","public"),t["name"]),(c["name"],)),[])
                    if matches: tags.extend(f"FK·{i}" for i,_ in matches)
                    out.append(f'<line x1="{x+12}" y1="{cy+7}" x2="{x+CW-12}" y2="{cy+7}" stroke="#edf1f5"/>')
                    txt(x+14,cy+19,c["name"],14,INK,600 if tags else 400)
                    txt(x+CW-14,cy+19,str(c.get("type","")),12,MUTED,400,"end")
                    suffix="  "+" ".join(tags)+( "  NULL" if c.get("nullable") else "  NOT NULL")
                    txt(x+14,cy+34,suffix.strip(),10,color if tags else MUTED,600)
                foot_i=0
                for ki,kc in enumerate(key_cons):
                    definition=kc.get("definition","")
                    # Present exact key column list when available from catalog DDL.
                    import re
                    match=re.search(r'\(([^()]*)\)',definition)
                    cols_text=match.group(1) if match else definition
                    txt(x+14,y+HEAD+22+LINE*len(rows)+FOOT*(foot_i+1)-5,f'{kc.get("type","KEY").replace("_"," ").upper()} ({cols_text})',10,color,600); foot_i+=1
                for ix in indexes:
                    definition=ix.get("definition","")
                    import re
                    m=re.search(r'\(([^()]*)\)',definition)
                    detail=(m.group(1) if m else ix.get("name",""))
                    pred=ix.get("predicate")
                    label=f'UQ INDEX ({detail})'+(f' WHERE {pred}' if pred else '')
                    txt(x+14,y+HEAD+22+LINE*len(rows)+FOOT*(foot_i+1)-5,label[:100],10,color,600); foot_i+=1
                y+=card_h+12
            y+=12
    actual_bottom=max(y+h for _,y,_,h in positions.values())
    cat_y=actual_bottom+30
    out.append(f'<rect x="{PAD}" y="{cat_y}" width="{W-2*PAD}" height="{cat_h}" rx="12" fill="#ffffff" stroke="#cfdae5" filter="url(#sh)"/>')
    txt(PAD+22,cat_y+35,"Relaciones declaradas en base de datos",21,INK,700)
    txt(PAD+22,cat_y+56,"Una fila por constraint FK; multiplicidad derivada de nulabilidad y claves únicas. No se infieren relaciones lógicas del servidor.",13,MUTED)
    colsx=[PAD+22, PAD+22+(W-2*PAD-44)//3, PAD+22+2*(W-2*PAD-44)//3]
    for i,f in enumerate(fks,1):
        cx=i//cat_rows; ry=i%cat_rows
        source=("auth." if f.get("source_schema")=="auth" else "")+f["source_table"]+"."+",".join(f["source_columns"])
        target=("auth." if f.get("target_schema")=="auth" else "")+f["target_table"]+"."+",".join(f["target_columns"])
        dele=f.get("on_delete") or "NO ACTION"
        source_table=next(t for t in tables if tkey(t.get("schema","public"),t["name"])==tkey(f.get("source_schema","public"),f["source_table"]))
        fk_cols=set(f["source_columns"])
        optional=any(c["name"] in fk_cols and c.get("nullable") for c in source_table["columns"])
        ref_card="0..1" if optional else "1"
        singleton=any(c.get("type","").lower() in ("primary_key","unique") and set(c.get("columns",[]))==fk_cols for c in source_table.get("constraints",[])) or any(ix.get("unique") and not ix.get("predicate") and set(__import__("re").search(r'\(([^()]*)\)',ix.get("definition","")).group(1).split(", "))==fk_cols for ix in source_table.get("unique_indexes",[]) if __import__("re").search(r'\(([^()]*)\)',ix.get("definition","") or ""))
        inverse="0..1" if singleton else "0..*"
        txt(colsx[cx],cat_y+83+ry*CAT_ROW,f'{i:02d}  {source} → {target}  [{dele}]  ({ref_card} : {inverse})',11,INK,400)
    legend_y=cat_y+cat_h-76
    txt(PAD+22,legend_y,"PK  clave primaria     UQ  unicidad individual     FK·n  referencia n     NULL / NOT NULL  nulabilidad real",13,INK,600)
    txt(PAD+22,legend_y+23,"auth.users es externa a la aplicación; se muestra únicamente su identificador para contextualizar sus referencias.",12,MUTED)
    rls=sum(1 for t in tables if t.get("schema")=="public" and t.get("rls_enabled"))
    txt(PAD+22,legend_y+45,f"RLS habilitado: {rls}/36 tablas públicas · constraints CHECK se conservan en backend_schema.json, el anexo completo del esquema.",12,MUTED)
    txt(PAD+22,legend_y+64,"Cardinalidad: FK-source → target : inverse. Inversa 0..* salvo PK/UQ total sobre la FK; nulabilidad determina 0..1 o 1.",11,MUTED)
    out.append('</svg>')
    SVG.write_text("\n".join(out),encoding="utf-8")
    PREVIEW.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="{round(H*1800/W)}" viewBox="0 0 {W} {H}"><image width="{W}" height="{H}" href="data:image/svg+xml;base64,{__import__("base64").b64encode("\n".join(out).encode()).decode()}"/></svg>',encoding="utf-8")
    print(f"Wrote {SVG} ({W} x {H}); {len(tables)} tables, {sum(len(t['columns']) for t in tables)} columns, {len(fks)} FKs")
if __name__=="__main__": main()
