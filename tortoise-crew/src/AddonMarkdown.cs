using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace TortoiseCrew
{
    // GitHub README is Markdown, not RTF. Render readable, styled text in WinForms,
    // and show Markdown images separately in the screenshots gallery.
    internal static class AddonMarkdown
    {
        private static readonly Regex Image = new Regex(
            @"!\[(?<label>[^\]]*)\]\(\s*(?<url><[^>]+>|[^)\s]+)(?:\s+""[^""]*"")?\s*\)",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex HtmlImage = new Regex(
            @"<img\b[^>]*?\bsrc\s*=\s*[""'](?<url>[^""']+)[""'][^>]*>",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);
        private static readonly Regex MarkdownLink = new Regex(
            @"(?<!!)\[(?<label>[^\]\r\n]+)\]\((?<url>https?://[^)\s]+)\)",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        internal static List<string> ImageUrls(string markdown, string baseRawUrl)
        {
            var urls = new List<string>();
            foreach (Match match in Image.Matches(markdown ?? ""))
                AddImage(urls, match.Groups["url"].Value.Trim('<', '>'), baseRawUrl);
            foreach (Match match in HtmlImage.Matches(markdown ?? ""))
                AddImage(urls, WebUtility.HtmlDecode(match.Groups["url"].Value), baseRawUrl);
            return urls.Distinct(StringComparer.OrdinalIgnoreCase).Take(35).ToList();
        }
        private static void AddImage(List<string> urls, string value, string baseRawUrl)
        {
            Uri uri;
            if (Uri.TryCreate(value, UriKind.Absolute, out uri))
            {
                if (uri.Scheme == Uri.UriSchemeHttps) urls.Add(uri.AbsoluteUri);
                return;
            }
            Uri baseUri;
            if (!Uri.TryCreate(baseRawUrl, UriKind.Absolute, out baseUri)) return;
            if (Uri.TryCreate(baseUri, value, out uri) && uri.Scheme == Uri.UriSchemeHttps)
                urls.Add(uri.AbsoluteUri);
        }
        internal static string CleanInline(string text)
        {
            string s = Image.Replace(text ?? "", m =>
            {
                var alt = m.Groups["label"].Value;
                return String.IsNullOrWhiteSpace(alt) ? "" : "[Screenshot: " + alt + "]";
            });
            s = HtmlImage.Replace(s, "");
            s = Regex.Replace(s, @"<!--.*?-->", "", RegexOptions.Singleline);
            s = Regex.Replace(s, @"</?(?:div|p|span|br|details|summary|center|kbd|small|strong|em|b|i)[^>]*>",
                " ", RegexOptions.IgnoreCase);
            s = MarkdownLink.Replace(s, m => m.Groups["label"].Value + " (" + m.Groups["url"].Value + ")");
            s = Regex.Replace(s, @"(?<!\*)\*\*([^*\r\n]+)\*\*", "$1");
            s = Regex.Replace(s, @"__([^_\r\n]+)__", "$1");
            s = Regex.Replace(s, @"(?<!\*)\*([^*\r\n]+)\*(?!\*)", "$1");
            s = Regex.Replace(s, @"~~([^~\r\n]+)~~", "$1");
            s = Regex.Replace(s, @"(?<!\w)_([^_\r\n]+)_(?!\w)", "$1");
            s = Regex.Replace(s, @"`([^`]+)`", "$1");
            return WebUtility.HtmlDecode(s).TrimEnd();
        }
        internal static string PlainText(string markdown)
        {
            var builder = new StringBuilder();
            foreach (var line in (markdown ?? "").Replace("\r\n", "\n").Split('\n'))
            {
                string content = Regex.Replace(line, @"^\s{0,3}#{1,6}\s+", "");
                content = CleanInline(content);
                builder.AppendLine(content);
            }
            return builder.ToString();
        }
        internal static void Render(RichTextBox target, string markdown)
        {
            target.SuspendLayout();
            try
            {
                target.Clear();
                bool code = false;
                int empty = 0;
                foreach (string original in (markdown ?? "").Replace("\r\n", "\n").Split('\n').Take(1500))
                {
                    string line = original.TrimEnd();
                    if (Regex.IsMatch(line, @"^\s*`{3,}"))
                    {
                        code = !code;
                        continue;
                    }
                    bool header = false;
                    int level = 0;
                    var head = Regex.Match(line, @"^\s{0,3}(#{1,6})\s+(.+)$");
                    if (head.Success)
                    {
                        header = true;
                        level = head.Groups[1].Length;
                        line = head.Groups[2].Value;
                    }
                    else
                    {
                        line = Regex.Replace(line, @"^\s*>\s?", "│ ");
                        line = Regex.Replace(line, @"^\s*[-*+]\s+", "• ");
                        line = Regex.Replace(line, @"^\s*([0-9]+)\.\s+", "$1. ");
                    }
                    line = CleanInline(line);
                    if (String.IsNullOrWhiteSpace(line))
                    {
                        if (++empty > 1) continue;
                    }
                    else empty = 0;
                    target.SelectionStart = target.TextLength;
                    target.SelectionLength = 0;
                    target.SelectionColor = header ? Color.FromArgb(98, 232, 190) :
                        code ? Color.FromArgb(201, 225, 243) : Color.FromArgb(234, 242, 251);
                    target.SelectionFont = new Font(code ? "Consolas" : "Segoe UI",
                        header ? (level <= 2 ? 14f : 11.5f) : 10.5f,
                        header ? FontStyle.Bold : FontStyle.Regular);
                    target.AppendText(line + "\n");
                }
                target.SelectionStart = 0;
                target.SelectionLength = 0;
                target.ScrollToCaret();
            }
            finally { target.ResumeLayout(); }
        }
    }
}
