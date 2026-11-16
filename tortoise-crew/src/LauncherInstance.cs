using System;
using System.Threading;

namespace TortoiseCrew
{
    internal sealed class LauncherInstance : IDisposable
    {
        private const string MutexName = @"Local\TortoiseCrewLauncherUi";
        internal const string ActivationName = @"Local\TortoiseCrewLauncherActivate";
        private Mutex mutex;

        private LauncherInstance(Mutex value) { mutex = value; }

        internal static LauncherInstance Acquire(int timeoutMilliseconds, string mutexName = MutexName)
        {
            var value = new Mutex(false, mutexName);
            bool acquired;
            try { acquired = value.WaitOne(timeoutMilliseconds); }
            catch (AbandonedMutexException) { acquired = true; }
            if (acquired) return new LauncherInstance(value);
            value.Dispose();
            return null;
        }

        internal static void ActivateExisting()
        {
            try
            {
                using (var signal = EventWaitHandle.OpenExisting(ActivationName)) signal.Set();
            }
            catch (WaitHandleCannotBeOpenedException) { }
        }

        public void Dispose()
        {
            if (mutex == null) return;
            mutex.ReleaseMutex();
            mutex.Dispose();
            mutex = null;
        }
    }
}
