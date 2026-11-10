"""Erzeugt aus doc_content.py: doc/dokumentation.md, doc/dokumentation.docx (-> PDF per Word) und doc/praesentation.pptx.

Aufruf:  python scripts/create_docs.py     (danach scripts/export_pdf.ps1 fuer die PDFs)
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image
from pptx import Presentation
from pptx.dml.color import RGBColor as PRGB
from pptx.enum.shapes import MSO_SHAPE
from pptx.util import Inches, Pt as PPt

sys.path.insert(0, str(Path(__file__).resolve().parent))
import doc_content as C  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "doc"
IMG = DOC / "img"
BLUE = "00549F"
RED = "E30015"
INLINE = re.compile(r"(\*\*.+?\*\*|`.+?`|(?<![\w*])\*[^*\s][^*]*?\*(?![\w*]))")


def slug(t):
    return re.sub(r"[^\w\- ]", "", t.lower()).replace(" ", "-")


# ------------------------------------------------------------------ Markdown

def make_md(path):
    out = [f"# {C.TITLE}", "", f"*{C.SUBTITLE}*", "",
           "Stand: 10.11.2026 | Bilder: `doc/img/` | PDF: `dokumentation.pdf` | Folien: `praesentation.pptx`", "",
           "## Inhalt", ""]
    for b in C.CONTENT:
        if b[0] == "h1":
            out.append(f"- [{b[1]}](#{slug(b[1])})")
    out.append("")
    fig = 0
    for b in C.CONTENT:
        k = b[0]
        if k == "h1":
            out += [f"## {b[1]}", ""]
        elif k == "h2":
            out += [f"### {b[1]}", ""]
        elif k == "h3":
            out += [f"#### {b[1]}", ""]
        elif k == "p":
            out += [b[1], ""]
        elif k == "ul":
            out += [f"- {i}" for i in b[1]] + [""]
        elif k == "ol":
            out += [f"{n}. {i}" for n, i in enumerate(b[1], 1)] + [""]
        elif k == "img":
            fig += 1
            out += [f"![Abbildung {fig}: {b[2]}](img/{b[1]})", "", f"*Abbildung {fig}: {b[2]}*", ""]
        elif k == "table":
            hd, rows = b[1], b[2]
            out.append("| " + " | ".join(hd) + " |")
            out.append("|" + "|".join(" --- " for _ in hd) + "|")
            for r in rows:
                out.append("| " + " | ".join(c.replace("|", "\\|") for c in r) + " |")
            out.append("")
        elif k == "code":
            lang = "powershell" if b[1].startswith("powershell") else "vhdl"
            out += [f"```{lang}", b[1], "```", ""]
        elif k == "note":
            label = {"info": "Hinweis", "warn": "Achtung", "tip": "Tipp"}[b[2]]
            out += [f"> **{label}:** {b[1]}", ""]
    path.write_text("\n".join(out), encoding="utf-8")


# ------------------------------------------------------------------ Word

def shade(cell, hex_):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_)
    tcPr.append(shd)


def cell_margins(table, top=50, bottom=50, left=90, right=90):
    tblPr = table._tbl.tblPr
    mar = OxmlElement("w:tblCellMar")
    for side, v in (("top", top), ("left", left), ("bottom", bottom), ("right", right)):
        el = OxmlElement(f"w:{side}")
        el.set(qn("w:w"), str(v))
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    tblPr.append(mar)


def runs(par, text, size=None, color=None, bold=False):
    for tok in INLINE.split(text):
        if not tok:
            continue
        if tok.startswith("**") and tok.endswith("**"):
            runs(par, tok[2:-2], size, color, True)
            continue
        if tok.startswith("`") and tok.endswith("`"):
            r = par.add_run(tok[1:-1])
            r.font.name = "Consolas"
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
            if size:
                r.font.size = Pt(size - 0.5)
        elif tok.startswith("*") and tok.endswith("*") and len(tok) > 2:
            r = par.add_run(tok[1:-1])
            r.italic = True
        else:
            r = par.add_run(tok)
        if bold:
            r.bold = True
        if size and not (tok.startswith("`")):
            r.font.size = Pt(size)
        if color:
            r.font.color.rgb = RGBColor.from_string(color)


def add_field(par, instr):
    run = par.add_run()
    for kind, text in (("begin", None), (None, instr), ("separate", None), (None, "1"), ("end", None)):
        if kind:
            el = OxmlElement("w:fldChar")
            el.set(qn("w:fldCharType"), kind)
        elif text == instr:
            el = OxmlElement("w:instrText")
            el.set(qn("xml:space"), "preserve")
            el.text = instr
        else:
            el = OxmlElement("w:t")
            el.text = text
        run._r.append(el)


def make_docx(path):
    doc = Document()
    sec = doc.sections[0]
    sec.page_height, sec.page_width = Cm(29.7), Cm(21)
    sec.top_margin = sec.bottom_margin = Cm(1.9)
    sec.left_margin = sec.right_margin = Cm(2)
    st = doc.styles["Normal"]
    st.font.name, st.font.size = "Calibri", Pt(10.5)
    st.paragraph_format.space_after = Pt(6)
    st.paragraph_format.line_spacing = 1.1
    for name, size in (("Heading 1", 20), ("Heading 2", 14.5), ("Heading 3", 12)):
        h = doc.styles[name]
        h.font.name, h.font.size, h.font.bold = "Calibri", Pt(size), True
        h.font.color.rgb = RGBColor.from_string(BLUE)
        h.element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
    doc.styles["Heading 1"].paragraph_format.space_before = Pt(0)
    doc.styles["Heading 1"].paragraph_format.space_after = Pt(10)
    doc.styles["Heading 2"].paragraph_format.space_before = Pt(14)
    doc.styles["Heading 3"].paragraph_format.space_before = Pt(10)
    hp = sec.header.paragraphs[0]
    hp.text = "prj_spi  |  Pmod OLEDrgb per SPI am Arty A7-35T"
    hp.runs[0].font.size = Pt(8.5)
    hp.runs[0].font.color.rgb = RGBColor(0x77, 0x77, 0x77)
    fp = sec.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = fp.add_run("Seite ")
    r.font.size = Pt(8.5)
    add_field(fp, "PAGE")

    # Titelseite
    for _ in range(3):
        doc.add_paragraph()
    t = doc.add_paragraph()
    run = t.add_run(C.TITLE)
    run.bold = True
    run.font.size = Pt(30)
    run.font.color.rgb = RGBColor.from_string(BLUE)
    s = doc.add_paragraph()
    run = s.add_run(C.SUBTITLE)
    run.font.size = Pt(13)
    run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
    bar = doc.add_paragraph()
    bar.paragraph_format.space_after = Pt(18)
    pPr = bar._p.get_or_add_pPr()
    pb = OxmlElement("w:pBdr")
    bt = OxmlElement("w:bottom")
    for k, v in (("val", "single"), ("sz", "24"), ("space", "1"), ("color", RED)):
        bt.set(qn(f"w:{k}"), v)
    pb.append(bt)
    pPr.append(pb)
    doc.add_picture(str(IMG / "22_lan_pong.png"), width=Cm(16.5))
    for line in ("Projekt: prj_spi (FPGA-Praktikum, Arty A7-35T)", "Stand: 10.11.2026",
                 "Verifikation: GHDL-Simulation bestanden; LAN-Betrieb auf echten Boards noch nicht erprobt",
                 "Autor / Gruppe: noch zu ergänzen"):
        p = doc.add_paragraph(line)
        p.runs[0].font.size = Pt(10.5)
    doc.add_page_break()
    doc.add_paragraph().add_run("Inhaltsverzeichnis").bold = True
    toc = doc.add_paragraph()
    add_field(toc, 'TOC \\o "1-2" \\h \\z \\u')
    doc.add_page_break()

    fig = 0
    first = True
    for b in C.CONTENT:
        k = b[0]
        if k == "h1":
            if not first and not b[1].startswith("Auf einen"):
                doc.add_page_break()
            first = False
            doc.add_heading(b[1].replace("`", ""), 1)
        elif k == "h2":
            doc.add_heading(b[1].replace("`", ""), 2)
        elif k == "h3":
            doc.add_heading(b[1].replace("`", ""), 3)
        elif k == "p":
            runs(doc.add_paragraph(), b[1])
        elif k in ("ul", "ol"):
            style = "List Bullet" if k == "ul" else "List Number"
            for item in b[1]:
                p = doc.add_paragraph(style=style)
                p.paragraph_format.space_after = Pt(3)
                runs(p, item)
        elif k == "img":
            fig += 1
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.keep_with_next = True
            p.add_run().add_picture(str(IMG / b[1]), width=Cm(16.5))
            cap = doc.add_paragraph()
            cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
            rr = cap.add_run(f"Abbildung {fig}: {b[2]}")
            rr.italic = True
            rr.font.size = Pt(9)
            rr.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
        elif k == "table":
            hd, rows, widths = b[1], b[2], b[3]
            tb = doc.add_table(rows=1, cols=len(hd))
            tb.style = "Table Grid"
            tb.alignment = WD_TABLE_ALIGNMENT.CENTER
            tb.autofit = False
            cell_margins(tb)
            for c, h in zip(tb.rows[0].cells, hd):
                shade(c, BLUE)
                c.paragraphs[0].paragraph_format.space_after = Pt(0)
                runs(c.paragraphs[0], h, 9.5, "FFFFFF", True)
            for ri, r in enumerate(rows):
                cells = tb.add_row().cells
                for c, text in zip(cells, r):
                    c.paragraphs[0].paragraph_format.space_after = Pt(0)
                    runs(c.paragraphs[0], text, 9.5)
                    if ri % 2 == 1:
                        shade(c, "F2F5F9")
            if widths:
                for row in tb.rows:
                    for c, w in zip(row.cells, widths):
                        c.width = Cm(w)
            doc.add_paragraph().paragraph_format.space_after = Pt(2)
        elif k == "code":
            tb = doc.add_table(rows=1, cols=1)
            tb.style = "Table Grid"
            cell_margins(tb, 70, 70, 120, 120)
            c = tb.rows[0].cells[0]
            shade(c, "F3F3F3")
            p = c.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing = 1.0
            lines = b[1].split("\n")
            for i, line in enumerate(lines):
                r = p.add_run(line)
                r.font.name = "Consolas"
                r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
                r.font.size = Pt(8)
                if i < len(lines) - 1:
                    r.add_break(WD_BREAK.LINE)
            doc.add_paragraph().paragraph_format.space_after = Pt(2)
        elif k == "note":
            fill = {"info": "DCEBFA", "warn": "FFF2BF", "tip": "DFF3E3"}[b[2]]
            label = {"info": "Hinweis: ", "warn": "Achtung: ", "tip": "Tipp: "}[b[2]]
            tb = doc.add_table(rows=1, cols=1)
            tb.style = "Table Grid"
            cell_margins(tb, 80, 80, 140, 140)
            c = tb.rows[0].cells[0]
            shade(c, fill)
            p = c.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            runs(p, f"**{label}**" + b[1], 10)
            doc.add_paragraph().paragraph_format.space_after = Pt(2)
    doc.save(path)


# ------------------------------------------------------------------ PowerPoint

SLIDES = [
    ("Pong am Arty A7", None, [], "", "title"),
    ("Aufgabe und Ergebnis", "15_moduswahl.png",
     ["Pong auf dem Pmod OLEDrgb (96 x 64, SPI) an Pmod JD des Arty A7-35T",
      "Ein Board oder zwei Boards über LAN; ein Bitstream, sw0 = Server/Client",
      "Nur ein Display? Am Client sw1 oben: LEDs zeigen die Punkte",
      "Alles als Schaltung in VHDL - kein Prozessor; Simulation bestanden"],
     "Ziel der Arbeit: Ein Farbdisplay über SPI ansteuern und darauf ein Spiel zeigen, das zwei Boards über Ethernet gemeinsam spielen. Betonen: Es gibt keinen Prozessor, jede Funktion ist eine Schaltung, die parallel zu den anderen läuft."),
    ("Hardware: Anschluss an JD", "03_hardware_anschluss.png",
     ["Pmod-Stecker passt 1:1: GND auf Pin 5/11, VCC (3,3 V) auf Pin 6/12",
      "JD ist ein Standard-Pmod mit 200-Ohm-Schutzwiderständen [1]",
      "Signale: CS, MOSI, SCK, D/C, RES, VCCEN, PMODEN [2]"],
     "Frage aus dem Projekt: Ist GND mit GND und VCC mit VCC verbunden? Ja, wenn das Modul direkt und nicht versetzt gesteckt ist. Prüfung per Messung: 3,3 V zwischen Pin 6 und Pin 5. Nie 5 V anlegen (max. 3,4 V an den Pmod-Pins)."),
    ("Was ist ein FPGA?", "01_fpga_grundlagen.png",
     ["LUT = Logikfunktion als Tabelle, Flip-Flop = 1 Bit Speicher",
      "Alle Bausteine arbeiten gleichzeitig im 100-MHz-Takt (10 ns)",
      "Man beschreibt eine Schaltung (VHDL), man programmiert nicht"],
     "Für Zuhörer ohne FPGA-Erfahrung: Der Unterschied zum Mikrocontroller ist die Parallelität. Register-Logik-Register ist das Grundmuster jeder Schaltung."),
    ("Vom VHDL-Text zum laufenden FPGA", "02_toolflow.png",
     ["Simulation (GHDL) prüft das Design am PC",
      "Vivado: Synthese, Implementierung (Pins aus der XDC), Bitstream",
      "Das Laden über USB-JTAG dauert ca. 6 s; die Konfiguration ist flüchtig [1]"],
     "Werkzeugkette erklären. Alle Quellen liegen in src/, die Pin-Zuordnung in constraints/."),
    ("Gesamtaufbau", "04_blockschaltbild_gesamt.png",
     ["input_filter: Sync + Entprellung für Schalter und Taster",
      "oled_render: Welche Farbe hat Pixel (x, y)?  oled_ctrl: Ablauf und Pixelzähler",
      "spi_tx: sendet jedes Byte seriell an das Display",
      "lan_link + eth_tx/eth_rx: Pong-Daten über den Ethernet-PHY"],
     "Datenfluss: Schalter, Render, Controller, SPI, Display. Der Controller fragt Pixel für Pixel nach der Farbe; es gibt keinen Bildspeicher im FPGA."),
    ("SPI Mode 3 - ein Byte", "05_spi_timing.png",
     ["SCK ruht auf 1; Bit wechselt bei fallender, wird bei steigender Flanke gelesen",
      "SCK = 100 MHz / 16 = 6,25 MHz (Datenblatt: min. 150 ns Periode) [2]",
      "D/C: 0 = Kommando, 1 = Pixeldaten"],
     "Am Beispiel 0xAE (Display aus) Bit für Bit erklären. Das Display kann nur empfangen; es gibt kein MISO."),
    ("SPI-Sender spi_tx", "06_spi_fsm.png",
     ["Fünf Zustände: IDLE, LEAD, LOW, HIGH, TRAIL",
      "hold = 1 hält CS für den ganzen Pixelstrom auf 0",
      "done meldet einen Takt lang: Byte fertig"],
     "Jeder Zustand wartet HALF = 8 Takte. Ein Byte dauert rund 140 Takte inklusive Vorlauf und Handshake."),
    ("Display einschalten", "08_einschaltsequenz.png",
     ["Reihenfolge: PMODEN, Reset, Konfiguration, dann erst VCCEN und Display-ein [2]",
      "37 Konfigurations-Bytes (Remap, Kontrast, Ströme ...)",
      "Zeiten: 20 ms, 100 µs, 3 ms, 25 ms, 100 ms"],
     "Die Panelspannung darf erst nach der Konfiguration kommen, sonst droht Schaden am OLED. Hinweis: Die Digilent-Liste enthält zusätzlich FD 12 und das Löschen des Bildspeichers; im Projekt wurden diese Schritte weggelassen und es läuft trotzdem."),
    ("Ablaufsteuerung oled_ctrl", "07_ctrl_fsm.png",
     ["Zustandsautomat: Strom, Reset, Init, VCC, Display ein, dann Bild-Schleife",
      "Pro Pixel: 12 Takte warten (Pipeline), Byte hi, Byte lo",
      "Nach dem letzten Pixel: frame_tick und zurück zum Kopf"],
     "ST_WAIT ist ein universeller Warteschritt mit Zähler. Die Bild-Schleife läuft endlos."),
    ("Ein Bild übertragen", "09_bildaufbau.png",
     ["96 x 64 = 6144 Pixel x 2 Byte = 12 288 Datenbytes pro Bild",
      "Kopf 15 00 5F 75 00 3F legt das Fenster fest; das Display zählt die Adresse selbst",
      "Zeile für Zeile, links nach rechts, oben nach unten"],
     "Wichtig: Der FPGA sendet nur die Pixel in der richtigen Reihenfolge, keine Adressen."),
    ("Farbe: RGB565", "10_rgb565.png",
     ["5 Bit Rot, 6 Bit Grün, 5 Bit Blau = 16 Bit pro Pixel",
      "Rot (227, 0, 21) = 0xE002; Pong nutzt nur Weiß 0xFFFF und Schwarz 0x0000",
      "Erst das obere, dann das untere Byte"],
     "Rechenbeispiel durchgehen: 227 geteilt durch 8 ist 28, das sind fünf Bit."),
    ("Zeitbedarf eines Bildes", "16_bildzeit.png",
     ["Pixel: 12 + 140 + 140 Takte = ca. 294 Takte = 2,94 µs",
      "6144 Pixel ca. 18 ms, rechnerisch ca. 55 Bilder pro Sekunde",
      "Rolle und Spiel ändern sich nur bei frame_tick"],
     "Die Bildrate ist berechnet, nicht gemessen. Weil sich nur am Bildende etwas ändert, zerreißt das Bild nicht."),
    ("Pong: Spielfeld", "17_pong_spielfeld.png",
     ["Feld = Display: 96 x 64; Schläger 2 x 14, Ball 3 x 3",
      "btn0/btn1 linker, btn2/btn3 rechter Schläger (über LAN: Tasten des Clients)",
      "Ball wird mit jedem Treffer schneller (max. 4 Pixel pro Bild)"],
     "Neun Punkte zum Sieg, danach Neustart. Der Verlierer des Punktes bekommt den Aufschlag."),
    ("Pong: Ablauf pro Bild", "18_pong_ablauf.png",
     ["Ein Spielschritt pro frame_tick (ca. 55 pro Sekunde)",
      "Wand, Treffer (x- und y-Überlappung), Tor",
      "Zufälliger Aufschlagwinkel aus einem LFSR"],
     "Beispiel aus der Dokumentation: Ball bei bx=12, vx=-3, Schläger bei y=25 - nach drei Bildern Treffer, vx wird +4."),
    ("Pong: Abprallwinkel", "19_pong_ablenkung.png",
     ["Vier Zonen auf dem Schläger: vy = -2, -1, +1, +2",
      "Außen steiler, innen flacher; nie waagerecht",
      "So lässt sich der Ball gezielt lenken"],
     "offset = Ballmitte relativ zur Schlägeroberkante."),
    ("Pong über LAN: Server und Client", "22_lan_pong.png",
     ["Server (sw0 unten) rechnet das Spiel, Client (sw0 oben) zeigt es und schickt seine Tasten",
      "Nur ein OLED: am Server; Client mit sw1 oben - Display aus, LEDs = eigene Punkte",
      "Ethernet-Rahmen an alle (Broadcast), EtherType 88B5, 64 Byte, ca. 55 pro Sekunde",
      "LD0 grün = Partner da; ohne Partner spielt der Server lokal, der Client wartet"],
     "Warum nur ein Spielstand: Zwei unabhängig rechnende Boards würden auseinanderlaufen. Der Client ist ein Fernseher mit Fernbedienung. Kein IP nötig - Direktkabel oder Switch genügen."),
    ("Pong über LAN: Technik", None,
     ["PHY TI DP83848J über MII: 4 Bit pro Takt, TX_CLK/RX_CLK 25 MHz vom PHY, 25-MHz-Grundtakt vom FPGA",
      "eth_tx/eth_rx: Präambel + SFD, Nibble für Nibble, CRC-32 (Rest DEBB20E3 = fehlerfrei)",
      "Drei Taktdomänen: Übergabe per Toggle-Handshake mit 2-FF-Synchronisierern",
      "Zeitüberwachung: 15 Bilder ohne gültigen Rahmen = getrennt"],
     "Toggle statt Puls: Eine Pegeländerung kann der andere Takt nicht verpassen. Die Sendedaten bleiben stabil, bis die Quittung zurück ist. Getestet mit zwei kompletten Designs in der Simulation; auf Hardware noch nicht erprobt."),
    ("Eingänge entprellen", "20_entprellung.png",
     ["2 Flip-Flops gegen Metastabilität, Zähler für 10 ms",
      "Taster: Ruhe 0, gedrückt 1; RESET: aktiv low [1]",
      "Reset wird einsynchronisiert und initialisiert das Display neu"],
     "Bedienlatenz: höchstens ca. 30 ms (10 ms Filter + bis zu einem Bild)."),
    ("Simulation und Tests", "21_testbench.png",
     ["SSD1331-Modell in der Testbench liest SPI mit und baut das Bild nach",
      "Geprüft: Init-Bytes, Pong-Bild, Server und Client mit/ohne OLED (Test-Server speist Rahmen ein)",
      "LAN: tb_eth (CRC, Bitfehler, 10 Mbit/s) und tb_lan_pong (zwei Boards, Kabel gestört/getrennt)",
      "Nicht geprüft: Timing auf dem Chip, Pins, Display-Orientierung"],
     "Die Simulation läuft mit schnellerem SPI-Takt und kürzeren Wartezeiten; die Logik ist dieselbe."),
    ("Fazit und Ausblick", None,
     ["Ergebnis: Pong für ein oder zwei Boards auf einem 96 x 64 Pixel Display, komplett in VHDL",
      "Gelernt: SPI, Display-Initialisierung, Pipeline, Zustandsautomaten, Testbench mit Gerätemodell",
      "Erweitert: Pong über LAN mit zwei Arty - Ethernet ohne Prozessor, direkt in VHDL",
      "Ideen: Siegertext in Pong, Pause-Schalter, höherer SPI-Takt, mehrere Pong-Paare im Netz"],
     "Zum Abschluss: Orientierung des Displays und Farbreihenfolge lassen sich über den Remap-Wert anpassen."),
    ("Quellen", None,
     ["[1] Digilent: Arty A7 Reference Manual - digilent.com/reference/programmable-logic/arty-a7/reference-manual",
      "[2] Digilent: Pmod OLEDrgb Reference Manual - digilent.com/reference/pmod/pmodoledrgb/reference-manual",
      "[3] Solomon Systech: SSD1331 Datasheet (in [2] verlinkt)",
      "[4] Digilent: Arty-A7-35-Master.xdc (Pin-Namen) - github.com/Digilent/digilent-xdc",
      "[6] TI: DP83848x Datenblatt SNLS250E;  [8] IEEE 802.3 (Rahmen, MII);  [9] IEEE: EtherType 88B5",
      "Zugriff: Seiten über Internet-Archive-Abbild (07.11.2024), direkter Abruf lieferte HTTP 403"],
     ""),
]


def fit(path, bx, by, bw, bh):
    w, h = Image.open(path).size
    s = min(bw / w, bh / h)
    return bx + (bw - w * s) / 2, by + (bh - h * s) / 2, w * s, h * s


def pt_text(slide, x, y, w, h, lines, size, color="1E1E24", bold=False, bullet=False):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = True
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = ("\u2022 " if bullet else "") + line
        p.font.size = PPt(size)
        p.font.bold = bold
        p.font.name = "Calibri"
        p.font.color.rgb = PRGB.from_string(color)
        p.space_after = PPt(6)
    return tb


def make_pptx(path):
    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)
    blank = prs.slide_layouts[6]
    total = len(SLIDES)
    for n, slide in enumerate(SLIDES, 1):
        title, img, bullets, notes = slide[:4]
        kind = slide[4] if len(slide) > 4 else "content"
        s = prs.slides.add_slide(blank)
        if kind == "title":
            bg = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
            bg.fill.solid()
            bg.fill.fore_color.rgb = PRGB.from_string(BLUE)
            bg.line.fill.background()
            pt_text(s, 0.8, 1.0, 11.7, 1.6, [C.TITLE], 40, "FFFFFF", True)
            pt_text(s, 0.8, 2.6, 11.7, 1.0, ["Pong 1 gegen 1  |  ein Board oder zwei Boards per LAN  |  Pmod OLEDrgb"], 22, "DDEBFA")
            pt_text(s, 0.8, 3.3, 11.7, 0.6, ["Projekt prj_spi  |  Digitale Schaltungstechnik  |  Autor / Gruppe: noch zu ergänzen"], 14, "DDEBFA")
            x, y, w, h = fit(IMG / "22_lan_pong.png", 0.8, 4.2, 11.7, 3.0)
            s.shapes.add_picture(str(IMG / "22_lan_pong.png"), Inches(x), Inches(y), Inches(w), Inches(h))
            s.notes_slide.notes_text_frame.text = "Titelfolie. Das Bild zeigt, was Server und Client austauschen."
            continue
        pt_text(s, 0.5, 0.3, 12.3, 0.8, [title], 30, BLUE, True)
        line = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(0.5), Inches(1.08), Inches(12.33), Inches(0.05))
        line.fill.solid()
        line.fill.fore_color.rgb = PRGB.from_string(RED)
        line.line.fill.background()
        if img:
            wd, ht = Image.open(IMG / img).size
            if wd / ht >= 1.9:
                x, y, w, h = fit(IMG / img, 0.5, 1.25, 12.33, 4.55)
                s.shapes.add_picture(str(IMG / img), Inches(x), Inches(y), Inches(w), Inches(h))
                pt_text(s, 0.6, 5.95, 12.1, 1.3, bullets, 18, bullet=True)
            else:
                x, y, w, h = fit(IMG / img, 0.4, 1.25, 8.3, 5.7)
                s.shapes.add_picture(str(IMG / img), Inches(x), Inches(y), Inches(w), Inches(h))
                pt_text(s, 8.9, 1.5, 4.1, 5.0, bullets, 18, bullet=True)
        else:
            pt_text(s, 0.8, 1.5, 11.7, 5.3, bullets, 22, bullet=True)
        pt_text(s, 0.5, 7.08, 9, 0.3, ["prj_spi  |  Pmod OLEDrgb per SPI am Arty A7-35T"], 10, "777777")
        pt_text(s, 11.8, 7.08, 1.1, 0.3, [f"{n} / {total}"], 10, "777777")
        s.notes_slide.notes_text_frame.text = notes
    prs.save(path)


def main():
    DOC.mkdir(exist_ok=True)
    make_md(DOC / "dokumentation.md")
    make_docx(DOC / "dokumentation.docx")
    make_pptx(DOC / "praesentation.pptx")
    print("md, docx, pptx geschrieben")


if __name__ == "__main__":
    main()
