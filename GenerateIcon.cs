using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

// Creates a reproducible multi-size ICO, with transparent edges and PNG frames.
internal static class GenerateIcon
{
    private static GraphicsPath Rounded(float x, float y, float w, float h, float radius)
    {
        float d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(x, y, d, d, 180, 90);
        p.AddArc(x + w - d, y, d, d, 270, 90);
        p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        p.AddArc(x, y + h - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    private static Bitmap Draw(int size)
    {
        var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.ScaleTransform(size / 256F, size / 256F);
            using (var handle = Rounded(85, 39, 86, 55, 14))
            using (var pen = new Pen(Color.FromArgb(28, 64, 119), 15))
                g.DrawPath(pen, handle);
            using (var body = Rounded(22, 75, 212, 154, 26))
            using (var brush = new LinearGradientBrush(new Rectangle(22, 75, 212, 154), Color.FromArgb(39, 142, 235), Color.FromArgb(20, 67, 159), 90F))
                g.FillPath(brush, body);
            using (var lid = Rounded(22, 75, 212, 51, 20))
            using (var brush = new SolidBrush(Color.FromArgb(64, 165, 248)))
                g.FillPath(brush, lid);
            using (var seam = new Pen(Color.FromArgb(70, 9, 47, 120), 4))
                g.DrawLine(seam, 25, 125, 231, 125);
            using (var latch = Rounded(113, 110, 30, 30, 6))
            using (var brush = new SolidBrush(Color.FromArgb(116, 234, 217)))
                g.FillPath(brush, latch);
            using (var pen = new Pen(Color.White, 12) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                g.DrawLines(pen, new[] { new PointF(75, 158), new PointF(94, 178), new PointF(75, 198) });
                g.DrawLine(pen, 125, 198, 177, 198);
            }
        }
        return bitmap;
    }

    private static void Main(string[] args)
    {
        if (args.Length != 1) throw new ArgumentException("Usage: GenerateIcon.exe output.ico");
        int[] sizes = { 16, 24, 32, 48, 64, 128, 256 };
        var frames = new List<byte[]>();
        foreach (int size in sizes)
        {
            using (var bitmap = Draw(size))
            using (var stream = new MemoryStream())
            {
                bitmap.Save(stream, ImageFormat.Png);
                frames.Add(stream.ToArray());
                if (size == 256) bitmap.Save(Path.ChangeExtension(args[0], ".png"), ImageFormat.Png);
            }
        }
        using (var writer = new BinaryWriter(File.Create(args[0])))
        {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)sizes.Length);
            int offset = 6 + sizes.Length * 16;
            for (int i = 0; i < sizes.Length; i++)
            {
                writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
                writer.Write((byte)0);
                writer.Write((byte)0);
                writer.Write((ushort)1);
                writer.Write((ushort)32);
                writer.Write(frames[i].Length);
                writer.Write(offset);
                offset += frames[i].Length;
            }
            foreach (byte[] frame in frames) writer.Write(frame);
        }
    }
}
