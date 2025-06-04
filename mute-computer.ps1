Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class Audio {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator {
        void NotImpl1();
        [PreserveSig]
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppEndpoint);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice {
        [PreserveSig]
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioEndpointVolume {
        void NotImpl1();
        void NotImpl2();
        [PreserveSig]
        int SetChannelVolumeLevelScalar(uint channelNumber, float level, Guid eventContext);
        [PreserveSig]
        int GetChannelVolumeLevelScalar(uint channelNumber, out float level);
        [PreserveSig]
        int GetChannelCount(out uint channelCount);
    }

    private enum EDataFlow {
        eRender,
        eCapture,
        eAll
    }

    private enum ERole {
        eConsole,
        eMultimedia,
        eCommunications
    }

    private const int CLSCTX_ALL = 0x1 | 0x2 | 0x4 | 0x10;

    public static void SetVolumeToMinimum() {
        IMMDeviceEnumerator deviceEnumerator = null;
        IMMDevice defaultDevice = null;
        object endpointVolume = null;
        IAudioEndpointVolume audioEndpoint = null;

        try {
            deviceEnumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            int hr = deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out defaultDevice);
            if (hr != 0 || defaultDevice == null) {
                throw new Exception("Failed to get default audio endpoint. Error code: " + hr);
            }

            Guid iid = typeof(IAudioEndpointVolume).GUID;
            hr = defaultDevice.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out endpointVolume);
            if (hr != 0 || endpointVolume == null) {
                throw new Exception("Failed to activate audio endpoint. Error code: " + hr);
            }
            audioEndpoint = (IAudioEndpointVolume)endpointVolume;

            // Get channel count
            uint channelCount;
            hr = audioEndpoint.GetChannelCount(out channelCount);
            if (hr != 0) {
                throw new Exception("Failed to get channel count. Error code: " + hr);
            }

            // Set volume to 0 for each channel
            for (uint i = 0; i < channelCount; i++) {
                hr = audioEndpoint.SetChannelVolumeLevelScalar(i, 0.0f, Guid.Empty);
                if (hr != 0) {
                    throw new Exception("Failed to set channel " + i + " volume. Error code: " + hr);
                }

                // Verify the change
                float level;
                hr = audioEndpoint.GetChannelVolumeLevelScalar(i, out level);
                if (hr != 0) {
                    throw new Exception("Failed to verify channel " + i + " volume. Error code: " + hr);
                }
                if (level > 0.01f) {
                    throw new Exception("Channel " + i + " volume did not change to 0. Current level: " + level);
                }
            }
        }
        catch (Exception ex) {
            throw new Exception("Failed to set volume to minimum: " + ex.Message);
        }
        finally {
            if (audioEndpoint != null) Marshal.ReleaseComObject(audioEndpoint);
            if (endpointVolume != null) Marshal.ReleaseComObject(endpointVolume);
            if (defaultDevice != null) Marshal.ReleaseComObject(defaultDevice);
            if (deviceEnumerator != null) Marshal.ReleaseComObject(deviceEnumerator);
        }
    }
}
'@

try {
    [Audio]::SetVolumeToMinimum()
    # Write-Host "Volume has been set to minimum level"
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
