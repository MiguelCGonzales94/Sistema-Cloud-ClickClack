#!/usr/bin/env python3
"""Genera el informe técnico en DOCX a partir de los capítulos Markdown de esta carpeta.

Uso:   python construir.py <carpeta_de_salida> [nombre_del_archivo_sin_extension]
Luego: powershell -File exportar-pdf.ps1 <docx> <pdf>      (Word actualiza el índice y exporta el PDF)

Subconjunto de Markdown admitido (el que usan los capítulos):
  # / ## / ###     títulos            - ítem / 1. ítem   listas
  | a | b |        tablas (precedidas por una línea "@tabla Título" para numerarlas)
  ![Título](ruta)  figura (ruta relativa al .md); con {paisaje} al final va en página apaisada
  ```              bloque de código    > texto           nota
  **negrita**, *cursiva*, `código`     ---pagina---      salto de página
"""
import json
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

AQUI = Path(__file__).resolve().parent
TITULO = "Sistema Cloud ClickClack"
COLOR = RGBColor(0x1F, 0x3A, 0x5F)

doc = Document()
n_tabla = 0
n_figura = 0
en_paisaje = False


# ---------------------------------------------------------------- utilidades de formato
def sombrear(celda, hex_color):
    tcPr = celda._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def campo(parrafo, instruccion):
    """Inserta un campo de Word (PAGE, TOC...) que Word calcula al abrir/exportar."""
    for tipo, texto in (("begin", None), (None, instruccion), ("separate", None), (None, " "), ("end", None)):
        run = parrafo.add_run()
        if tipo:
            f = OxmlElement("w:fldChar")
            f.set(qn("w:fldCharType"), tipo)
            run._r.append(f)
        elif texto is not None and texto.strip() == instruccion.strip():
            t = OxmlElement("w:instrText")
            t.set(qn("xml:space"), "preserve")
            t.text = instruccion
            run._r.append(t)
        else:
            run.text = texto


def configurar_estilos():
    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(11)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.12
    for nombre, tam in (("Heading 1", 18), ("Heading 2", 14), ("Heading 3", 12)):
        h = doc.styles[nombre]
        h.font.name = "Calibri"
        h.font.size = Pt(tam)
        h.font.bold = True
        h.font.color.rgb = COLOR
        h.element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
        h.paragraph_format.space_before = Pt(16 if nombre == "Heading 1" else 12)
        h.paragraph_format.space_after = Pt(6)
        h.paragraph_format.keep_with_next = True
    seccion = doc.sections[0]
    seccion.page_width, seccion.page_height = Cm(21.0), Cm(29.7)
    seccion.left_margin = seccion.right_margin = Cm(2.3)
    seccion.top_margin = seccion.bottom_margin = Cm(2.2)


def pie_de_pagina(seccion):
    seccion.footer.is_linked_to_previous = False
    p = seccion.footer.paragraphs[0]
    p.text = ""
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(f"{TITULO} · Informe técnico · Servicios Cloud (UTP) · página ")
    r.font.size = Pt(8.5)
    r.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    campo(p, " PAGE ")
    for run in p.runs:
        run.font.size = Pt(8.5)


def asegurar_vertical():
    """Vuelve a página vertical si la última figura dejó la sección en apaisado."""
    global en_paisaje
    if not en_paisaje:
        return
    vuelta = doc.add_section()
    vuelta.orientation = WD_ORIENT.PORTRAIT
    vuelta.page_width, vuelta.page_height = Cm(21.0), Cm(29.7)
    vuelta.left_margin = vuelta.right_margin = Cm(2.3)
    vuelta.top_margin = vuelta.bottom_margin = Cm(2.2)
    pie_de_pagina(vuelta)
    en_paisaje = False


# ---------------------------------------------------------------- texto en línea
PATRON = re.compile(r"(\*\*\*[^*]+\*\*\*|\*\*(?:[^*]|\*[^*]+\*)+\*\*|`[^`]+`|\*[^*\s][^*]*\*)")


def en_linea(parrafo, texto, tam=None, negrita=False, cursiva=False):
    for trozo in PATRON.split(texto):
        if not trozo:
            continue
        if trozo.startswith("***") and trozo.endswith("***") and len(trozo) > 6:
            en_linea(parrafo, trozo[3:-3], tam, True, True)
            continue
        if trozo.startswith("**") and trozo.endswith("**") and len(trozo) > 4:
            en_linea(parrafo, trozo[2:-2], tam, True, cursiva)
            continue
        if trozo.startswith("`") and trozo.endswith("`") and len(trozo) > 2:
            run = parrafo.add_run(trozo[1:-1])
            run.font.name = "Consolas"
            run._r.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), "Consolas")
            run.font.size = Pt((tam or 11) - 1.5)
            run.bold = negrita or None
            continue
        if trozo.startswith("*") and trozo.endswith("*") and len(trozo) > 2:
            en_linea(parrafo, trozo[1:-1], tam, negrita, True)
            continue
        run = parrafo.add_run(trozo)
        run.bold = negrita or None
        run.italic = cursiva or None
        if tam:
            run.font.size = Pt(tam)


# ---------------------------------------------------------------- bloques
def titulo(nivel, texto):
    asegurar_vertical()
    h = doc.add_heading(re.sub(r"[`*]", "", texto), level=nivel)
    if nivel == 1:
        h.paragraph_format.page_break_before = True


def parrafo(texto):
    asegurar_vertical()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    en_linea(p, texto)


def lista(items, numerada):
    asegurar_vertical()
    for n, texto in enumerate(items, 1):
        if numerada:
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.9)
            p.paragraph_format.first_line_indent = Cm(-0.6)
            p.add_run(f"{n}. ")
            p.paragraph_format.space_after = Pt(2)
        else:
            p = doc.add_paragraph(style="List Bullet")
            p.paragraph_format.space_after = Pt(2)
        en_linea(p, texto)


def nota(texto):
    asegurar_vertical()
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    c = t.rows[0].cells[0]
    sombrear(c, "EEF4FF")
    c.paragraphs[0].text = ""
    en_linea(c.paragraphs[0], texto, tam=10)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def codigo(lineas):
    asegurar_vertical()
    t = doc.add_table(rows=1, cols=1)
    c = t.rows[0].cells[0]
    sombrear(c, "F2F4F7")
    c.paragraphs[0].text = ""
    for i, linea in enumerate(lineas):
        p = c.paragraphs[0] if i == 0 else c.add_paragraph()
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.0
        r = p.add_run(linea.rstrip() or " ")
        r.font.name = "Consolas"
        r._r.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), "Consolas")
        r.font.size = Pt(8)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def tabla(titulo_tabla, filas):
    global n_tabla
    asegurar_vertical()
    filas = [f for f in filas if not re.fullmatch(r"\s*\|?[\s:|-]+\|?\s*", f)]
    celdas = [[c.strip() for c in f.strip().strip("|").split("|")] for f in filas]
    cols = max(len(f) for f in celdas)
    if titulo_tabla:
        n_tabla += 1
        p = doc.add_paragraph()
        p.paragraph_format.keep_with_next = True
        p.paragraph_format.space_after = Pt(3)
        r = p.add_run(f"Tabla {n_tabla}. ")
        r.bold = True
        r.font.size = Pt(9.5)
        en_linea(p, titulo_tabla, tam=9.5)
    t = doc.add_table(rows=len(celdas), cols=cols)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    # ancho de cada columna según su contenido (las columnas cortas, como "#", quedan angostas)
    largos = [max(len(re.sub(r"[`*]", "", f[j])) if j < len(f) else 0 for f in celdas) for j in range(cols)]
    pesos = [max(9, min(l, 90)) ** 0.7 for l in largos]
    total = sum(pesos)
    t.autofit = False
    anchos = [Cm(16.4 * p / total) for p in pesos]
    for i, fila in enumerate(celdas):
        for j in range(cols):
            c = t.rows[i].cells[j]
            c.paragraphs[0].text = ""
            c.paragraphs[0].paragraph_format.space_after = Pt(1)
            texto = fila[j] if j < len(fila) else ""
            c.width = anchos[j]
            en_linea(c.paragraphs[0], texto, tam=8.5, negrita=(i == 0))
            if i == 0:
                sombrear(c, "DCE6F2")
    # repetir la fila de encabezado si la tabla cruza de página
    trPr = t.rows[0]._tr.get_or_add_trPr()
    th = OxmlElement("w:tblHeader")
    th.set(qn("w:val"), "true")
    trPr.append(th)
    doc.add_paragraph().paragraph_format.space_after = Pt(4)


def figura(texto, ruta, base, paisaje):
    global n_figura, en_paisaje
    n_figura += 1
    archivo = (base / ruta).resolve()
    if not archivo.exists():
        raise SystemExit(f"Falta la imagen: {archivo}")
    from docx.image.image import Image as ImagenDocx
    img = ImagenDocx.from_file(str(archivo))
    proporcion = img.px_width / img.px_height
    if paisaje:
        if en_paisaje:
            doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
        else:
            nueva = doc.add_section()
            nueva.orientation = WD_ORIENT.LANDSCAPE
            nueva.page_width, nueva.page_height = Cm(29.7), Cm(21.0)
            nueva.left_margin = nueva.right_margin = Cm(1.5)
            nueva.top_margin = nueva.bottom_margin = Cm(1.5)
            pie_de_pagina(nueva)
            en_paisaje = True
        # alto útil ≈ 18 cm menos la leyenda: se limita a 15,8 cm
        ancho = Cm(min(26.2, 15.8 * proporcion))
    else:
        asegurar_vertical()
        ancho = Cm(min(16.2, 20.0 * proporcion))
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(str(archivo), width=ancho)
    c = doc.add_paragraph()
    c.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = c.add_run(f"Figura {n_figura}. ")
    r.bold = True
    r.font.size = Pt(9.5)
    en_linea(c, texto, tam=9.5)


def salto():
    global en_paisaje
    if en_paisaje:
        asegurar_vertical()  # la nueva sección ya empieza en página nueva
        return
    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)


# ---------------------------------------------------------------- portada e índice
def cargar_portada(salida):
    """Datos de la portada: <salida>/portada.json (local, fuera de git) o portada.ejemplo.json."""
    for ruta in (salida / "portada.json", AQUI / "portada.ejemplo.json"):
        if ruta.exists():
            return json.loads(ruta.read_text(encoding="utf-8"))
    raise SystemExit("Falta portada.json")


def linea(texto, tam=12, negrita=False, color=None, antes=0, despues=6):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(antes)
    p.paragraph_format.space_after = Pt(despues)
    r = p.add_run(texto)
    r.font.size = Pt(tam)
    r.bold = negrita
    if color:
        r.font.color.rgb = color
    return p


def portada(datos):
    gris = RGBColor(0x55, 0x55, 0x55)
    linea(datos["facultad"], 13, color=gris, antes=40, despues=2)
    linea(datos["carrera"], 13, color=gris, despues=2)
    linea(datos["curso"], 13, True, color=gris, despues=60)
    linea(datos["titulo"], 34, True, COLOR, despues=10)
    linea(datos["subtitulo"], 15, color=COLOR, despues=40)
    linea(datos["entrega"], 14, True, despues=40)
    linea("Autores", 12, True, despues=4)
    for a in datos["autores"]:
        linea(a, 11, despues=1)
    linea("Docente", 12, True, antes=18, despues=4)
    linea(datos["docente"], 11, despues=30)
    linea(datos["lugar"], 11, despues=1)
    linea(datos["fecha"], 11, despues=14)
    if datos.get("repositorio"):
        linea("Repositorio público: " + datos["repositorio"], 10, color=gris)
    salto()
    p = doc.add_paragraph()
    r = p.add_run("Contenido")
    r.bold = True
    r.font.size = Pt(18)
    r.font.color.rgb = COLOR
    campo(doc.add_paragraph(), ' TOC \\o "1-2" \\h \\z \\u ')


# ---------------------------------------------------------------- lector de Markdown
def procesar(ruta_md):
    base = ruta_md.parent
    lineas = ruta_md.read_text(encoding="utf-8").splitlines()
    i = 0
    parr = []
    pendiente_tabla = None

    def vaciar():
        nonlocal parr
        if parr:
            parrafo(" ".join(parr))
            parr = []

    while i < len(lineas):
        l = lineas[i]
        s = l.strip()
        if s.startswith("```"):
            vaciar()
            bloque = []
            i += 1
            while i < len(lineas) and not lineas[i].strip().startswith("```"):
                bloque.append(lineas[i])
                i += 1
            codigo(bloque)
        elif s == "---pagina---":
            vaciar()
            salto()
        elif s.startswith("@tabla "):
            vaciar()
            pendiente_tabla = s[7:].strip()
        elif s.startswith("|"):
            vaciar()
            filas = []
            while i < len(lineas) and lineas[i].strip().startswith("|"):
                filas.append(lineas[i])
                i += 1
            tabla(pendiente_tabla, filas)
            pendiente_tabla = None
            continue
        elif s.startswith("!["):
            vaciar()
            m = re.match(r"!\[(.*?)\]\((.*?)\)(\{paisaje\})?", s)
            figura(m.group(1), m.group(2), base, bool(m.group(3)))
        elif re.match(r"#{1,3} ", s):
            vaciar()
            nivel = len(s) - len(s.lstrip("#"))
            titulo(nivel, s[nivel:].strip())
        elif s.startswith("> "):
            vaciar()
            nota(s[2:])
        elif re.match(r"- ", s):
            vaciar()
            items = []
            while i < len(lineas) and lineas[i].strip().startswith("- "):
                items.append(lineas[i].strip()[2:])
                i += 1
            lista(items, False)
            continue
        elif re.match(r"\d+\. ", s):
            vaciar()
            items = []
            while i < len(lineas) and re.match(r"\d+\. ", lineas[i].strip()):
                items.append(re.sub(r"^\d+\.\s+", "", lineas[i].strip()))
                i += 1
            lista(items, True)
            continue
        elif not s:
            vaciar()
        else:
            parr.append(s)
        i += 1
    vaciar()


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    salida = Path(sys.argv[1])
    nombre = sys.argv[2] if len(sys.argv) == 3 else f"Informe tecnico - {TITULO}"
    salida.mkdir(parents=True, exist_ok=True)
    configurar_estilos()
    pie_de_pagina(doc.sections[0])
    doc.sections[0].different_first_page_header_footer = True
    portada(cargar_portada(salida))
    capitulos = sorted(p for p in AQUI.glob("[0-9][0-9]-*.md"))
    if not capitulos:
        raise SystemExit("No hay capítulos NN-*.md")
    for cap in capitulos:
        procesar(cap)
    doc.core_properties.title = f"{TITULO} — Informe técnico"
    doc.core_properties.author = "Equipo ClickClak"
    destino = salida / f"{nombre}.docx"
    doc.save(destino)
    print(f"DOCX: {destino}  (tablas: {n_tabla}, figuras: {n_figura}, capítulos: {len(capitulos)})")


if __name__ == "__main__":
    main()
