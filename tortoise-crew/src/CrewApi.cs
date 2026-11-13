using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace TortoiseCrew
{
    internal sealed class CrewReply
    {
        public bool ok { get; set; }
        public string code { get; set; }
        public string token { get; set; }
        public Dictionary<string, bool> online { get; set; }
    }

    internal static class CrewApi
    {
        private static string Endpoint(LauncherSettings settings, string path)
        {
            Uri uri;
            if (settings == null || !Uri.TryCreate(settings.CrewApiUrl, UriKind.Absolute, out uri) ||
                uri.Scheme != Uri.UriSchemeHttps ||
                (!uri.Host.EndsWith(".trycloudflare.com", StringComparison.OrdinalIgnoreCase) &&
                 !uri.Host.EndsWith(".altare.global", StringComparison.OrdinalIgnoreCase) &&
                 !uri.Host.EndsWith(".go.altare.global", StringComparison.OrdinalIgnoreCase)) ||
                uri.Port != 443 || !String.IsNullOrEmpty(uri.UserInfo))
                throw new InvalidOperationException("The secure Crew service is not configured.");
            return uri.GetLeftPart(UriPartial.Authority) + path;
        }

        private static async Task<CrewReply> CallAsync(LauncherSettings settings, string path,
                                                       object body = null)
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var request = (HttpWebRequest)WebRequest.Create(Endpoint(settings, path));
            request.Method = body == null ? "GET" : "POST";
            request.ContentType = "application/json";
            request.Accept = "application/json";
            request.Timeout = 9000;
            request.ReadWriteTimeout = 9000;
            request.Proxy = null;
            if (body != null)
            {
                byte[] bytes = Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(body));
                if (bytes.Length > 2048) throw new InvalidOperationException("Request too large.");
                request.ContentLength = bytes.Length;
                using (var stream = await request.GetRequestStreamAsync())
                    await stream.WriteAsync(bytes, 0, bytes.Length);
            }
            try
            {
                using (var response = (HttpWebResponse)await request.GetResponseAsync())
                using (var stream = new StreamReader(response.GetResponseStream()))
                {
                    var json = await stream.ReadToEndAsync();
                    if (json.Length > 8192) throw new InvalidDataException("Crew service response too large.");
                    return new JavaScriptSerializer().Deserialize<CrewReply>(json);
                }
            }
            catch (WebException ex)
            {
                if (ex.Response != null)
                {
                    using (var response = ex.Response)
                    using (var reader = new StreamReader(response.GetResponseStream()))
                    {
                        var json = await reader.ReadToEndAsync();
                        if (json.Length < 8192)
                        {
                            try
                            {
                                var problem = new JavaScriptSerializer().Deserialize<CrewReply>(json);
                                if (problem != null && !String.IsNullOrEmpty(problem.code))
                                    throw new InvalidOperationException(problem.code);
                            }
                            catch (System.ArgumentException) { }
                        }
                    }
                }
                throw new InvalidOperationException("Crew service is unavailable.", ex);
            }
        }

        internal static async Task<string> LoginAsync(LauncherSettings settings, string user,
                                                       string password)
        {
            var reply = await CallAsync(settings, "/v1/session",
                new { username = user, password = password });
            if (reply == null || !reply.ok || String.IsNullOrEmpty(reply.token) ||
                reply.token.Length != 64)
                throw new InvalidOperationException("The game account password was not accepted.");
            return reply.token;
        }

        internal static async Task ChangePasswordAsync(LauncherSettings settings, string user,
                                                       string current, string desired)
        {
            var reply = await CallAsync(settings, "/v1/password",
                new { username = user, currentPassword = current, newPassword = desired });
            if (reply == null || !reply.ok || reply.code != "PASSWORD_UPDATED")
                throw new InvalidOperationException("The password could not be changed.");
        }

        internal static async Task<Dictionary<string, bool>> PresenceAsync(LauncherSettings settings)
        {
            var reply = await CallAsync(settings, "/v1/presence");
            return reply != null && reply.ok ? reply.online : null;
        }

        internal static async Task<bool> IsOnlineAsync(LauncherSettings settings)
        {
            var reply = await CallAsync(settings, "/v1/health");
            return reply != null && reply.ok;
        }

        internal static Uri WebSocketEndpoint(LauncherSettings settings, string mode)
        {
            var http = new Uri(Endpoint(settings, "/v1/relay/" + mode));
            return new UriBuilder(http) { Scheme = "wss", Port = 443 }.Uri;
        }
    }
}
