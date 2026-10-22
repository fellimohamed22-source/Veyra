package com.veyra.finance;

import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Minimal single-page A4 PDF writer for invoices: standard Helvetica fonts
 * (WinAnsi, so French accents and the euro sign print), text, lines and
 * filled rectangles. No dependency; coordinates in points from the top.
 */
final class SimplePdf {
  static final float WIDTH = 595.28f, HEIGHT = 841.89f;
  private static final Charset WIN_ANSI = Charset.forName("windows-1252");
  // Advance widths (1/1000 em) of characters 32..126, Adobe AFM metrics.
  private static final int[] REGULAR = {278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584};
  private static final int[] BOLD = {278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584};

  private final StringBuilder content = new StringBuilder();

  /** Text whose baseline is {@code top} points below the page top. */
  SimplePdf text(float x, float top, float size, boolean bold, String s) {
    content.append("BT /").append(bold ? "F2" : "F1").append(' ').append(n(size)).append(" Tf ")
        .append(n(x)).append(' ').append(n(HEIGHT - top)).append(" Td ").append(literal(s)).append(" Tj ET\n");
    return this;
  }

  SimplePdf textRight(float right, float top, float size, boolean bold, String s) {
    return text(right - width(s, size, bold), top, size, bold, s);
  }

  /** Wraps {@code s} to {@code maxWidth}; returns the top of the next line. */
  float paragraph(float x, float top, float size, boolean bold, float maxWidth, String s) {
    float leading = size * 1.35f;
    for (String line : wrap(s, size, bold, maxWidth)) {
      text(x, top, size, bold, line);
      top += leading;
    }
    return top;
  }

  SimplePdf line(float x1, float top1, float x2, float top2, float gray) {
    content.append(n(gray)).append(" G 0.6 w ").append(n(x1)).append(' ').append(n(HEIGHT - top1)).append(" m ")
        .append(n(x2)).append(' ').append(n(HEIGHT - top2)).append(" l S\n");
    return this;
  }

  SimplePdf fill(float x, float top, float w, float h, float r, float g, float b) {
    content.append(n(r)).append(' ').append(n(g)).append(' ').append(n(b)).append(" rg ")
        .append(n(x)).append(' ').append(n(HEIGHT - top - h)).append(' ').append(n(w)).append(' ').append(n(h)).append(" re f 0 g\n");
    return this;
  }

  SimplePdf color(float r, float g, float b) {
    content.append(n(r)).append(' ').append(n(g)).append(' ').append(n(b)).append(" rg\n");
    return this;
  }

  static float width(String s, float size, boolean bold) {
    int[] w = bold ? BOLD : REGULAR;
    float total = 0;
    for (char c : clean(s).toCharArray()) {
      char base = baseLetter(c);
      total += base >= 32 && base <= 126 ? w[base - 32] : 556;
    }
    return total * size / 1000f;
  }

  static List<String> wrap(String s, float size, boolean bold, float maxWidth) {
    List<String> lines = new ArrayList<>();
    for (String para : (s == null ? "" : s).split("\n")) {
      StringBuilder line = new StringBuilder();
      for (String word : para.split(" ")) {
        String candidate = line.isEmpty() ? word : line + " " + word;
        if (width(candidate, size, bold) <= maxWidth || line.isEmpty()) line = new StringBuilder(candidate);
        else { lines.add(line.toString()); line = new StringBuilder(word); }
      }
      lines.add(line.toString());
    }
    return lines;
  }

  byte[] toBytes() {
    byte[] stream = content.toString().getBytes(StandardCharsets.ISO_8859_1);
    List<String> objects = List.of(
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 " + n(WIDTH) + " " + n(HEIGHT) + "] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    List<Integer> offsets = new ArrayList<>();
    write(out, "%PDF-1.4\n%âãÏÓ\n");
    for (int i = 0; i < objects.size(); i++) {
      offsets.add(out.size());
      write(out, (i + 1) + " 0 obj\n" + objects.get(i) + "\nendobj\n");
    }
    offsets.add(out.size());
    write(out, "6 0 obj\n<< /Length " + stream.length + " >>\nstream\n");
    out.writeBytes(stream);
    write(out, "\nendstream\nendobj\n");
    int xref = out.size();
    StringBuilder x = new StringBuilder("xref\n0 7\n0000000000 65535 f \n");
    for (int o : offsets) x.append(String.format("%010d 00000 n \n", o));
    x.append("trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n").append(xref).append("\n%%EOF\n");
    write(out, x.toString());
    return out.toByteArray();
  }

  private static void write(ByteArrayOutputStream out, String s) { out.writeBytes(s.getBytes(StandardCharsets.ISO_8859_1)); }

  /** PDF string literal in WinAnsi, non-ASCII bytes as octal escapes. */
  static String literal(String s) {
    StringBuilder b = new StringBuilder("(");
    for (byte raw : clean(s).getBytes(WIN_ANSI)) {
      int c = raw & 0xff;
      if (c == '(' || c == ')' || c == '\\') b.append('\\').append((char) c);
      else if (c < 32 || c > 126) b.append('\\').append(String.format("%03o", c));
      else b.append((char) c);
    }
    return b.append(')').toString();
  }

  /** Characters WinAnsi lacks (narrow no-break spaces from French formats, arrows). */
  private static String clean(String s) {
    if (s == null) return "";
    return s.replace(' ', ' ').replace(' ', ' ').replace("→", "->").replace('‑', '-');
  }

  private static char baseLetter(char c) {
    String folded = java.text.Normalizer.normalize(String.valueOf(c), java.text.Normalizer.Form.NFD);
    return folded.isEmpty() ? c : folded.charAt(0);
  }

  private static String n(float v) {
    String s = String.format(java.util.Locale.ROOT, "%.2f", v);
    return s.endsWith(".00") ? s.substring(0, s.length() - 3) : s;
  }
}
