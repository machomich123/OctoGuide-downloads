using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Threading;
using System.Threading.Tasks;

namespace TortoiseCrew
{
    // Two local loopback listeners tunnel only WoW's authentication and world
    // TCP streams through an authenticated, end-to-end TLS WebSocket session.
    // No SSH credentials or administrative server privileges are present.
    internal sealed class CrewBridge : IDisposable
    {
        private readonly LauncherSettings settings;
        private readonly string token;
        private readonly CancellationTokenSource stop = new CancellationTokenSource();
        private TcpListener authListener;
        private TcpListener worldListener;

        public CrewBridge(LauncherSettings settings, string sessionToken)
        {
            this.settings = settings;
            token = sessionToken;
        }

        public void Start()
        {
            try
            {
                authListener = new TcpListener(IPAddress.Loopback, 3724);
                authListener.Start(8);
                worldListener = new TcpListener(IPAddress.Loopback, 8085);
                worldListener.Start(8);
                _ = AcceptAsync(authListener, "auth");
                _ = AcceptAsync(worldListener, "world");
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        private async Task AcceptAsync(TcpListener listener, string mode)
        {
            while (!stop.IsCancellationRequested)
            {
                TcpClient local;
                try { local = await listener.AcceptTcpClientAsync(); }
                catch (ObjectDisposedException) { break; }
                catch (SocketException) { if (stop.IsCancellationRequested) break; else throw; }
                _ = ProxyAsync(local, mode);
            }
        }

        private async Task ProxyAsync(TcpClient local, string mode)
        {
            using (local)
            using (var ws = new ClientWebSocket())
            using (var linked = CancellationTokenSource.CreateLinkedTokenSource(stop.Token))
            {
                try
                {
                    ws.Options.SetRequestHeader("Authorization", "Bearer " + token);
                    ws.Options.KeepAliveInterval = TimeSpan.FromSeconds(20);
                    await ws.ConnectAsync(CrewApi.WebSocketEndpoint(settings, mode), linked.Token);
                    using (var stream = local.GetStream())
                    {
                        Task upstream = ToWebSocket(stream, ws, linked.Token);
                        Task downstream = ToTcp(ws, stream, linked.Token);
                        await Task.WhenAny(upstream, downstream);
                    }
                }
                catch (Exception ex)
                {
                    if (!stop.IsCancellationRequested)
                        Paths.WriteLog("Game bridge connection ended: " + ex.GetType().Name);
                }
                finally
                {
                    linked.Cancel();
                    ws.Abort();
                }
            }
        }

        private static async Task ToWebSocket(Stream stream, ClientWebSocket ws, CancellationToken cancel)
        {
            var buffer = new byte[8192];
            while (!cancel.IsCancellationRequested)
            {
                int count = await stream.ReadAsync(buffer, 0, buffer.Length, cancel);
                if (count <= 0) break;
                await ws.SendAsync(new ArraySegment<byte>(buffer, 0, count),
                                   WebSocketMessageType.Binary, true, cancel);
            }
        }

        private static async Task ToTcp(ClientWebSocket ws, Stream stream, CancellationToken cancel)
        {
            var buffer = new byte[8192];
            while (!cancel.IsCancellationRequested && ws.State == WebSocketState.Open)
            {
                var result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), cancel);
                if (result.MessageType == WebSocketMessageType.Close) break;
                if (result.MessageType != WebSocketMessageType.Binary)
                    throw new InvalidDataException("Unexpected non-game relay message.");
                if (result.Count > 0)
                    await stream.WriteAsync(buffer, 0, result.Count, cancel);
            }
        }

        public void Dispose()
        {
            if (!stop.IsCancellationRequested) stop.Cancel();
            if (authListener != null) authListener.Stop();
            if (worldListener != null) worldListener.Stop();
        }
    }
}
