function Read-WimInfo {
    param([Parameter(Mandatory)][string]$ImagePath)
    $fullPath = (Resolve-Path -LiteralPath $ImagePath).Path
    if (-not ('DNW.WimQuery' -as [type])) {
        # API nativa da Microsoft. Acesso 0 = consulta; disposition 3 = OPEN_EXISTING.
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace DNW {
  public static class WimQuery {
    [DllImport("wimgapi.dll", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
    static extern IntPtr WIMCreateFile(string path, uint access, uint disposition, uint flags, uint compression, out uint result);
    [DllImport("wimgapi.dll", ExactSpelling=true, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool WIMGetImageInformation(IntPtr image, out IntPtr xml, out uint bytes);
    [DllImport("wimgapi.dll", ExactSpelling=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool WIMCloseHandle(IntPtr image);
    [DllImport("kernel32.dll", ExactSpelling=true)]
    static extern IntPtr LocalFree(IntPtr memory);
    public static string ReadXml(string path) {
      uint result;
      IntPtr image = WIMCreateFile(path, 0, 3, 0, 0, out result);
      if (image == IntPtr.Zero || image == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
      IntPtr xml = IntPtr.Zero;
      try {
        uint bytes;
        if (!WIMGetImageInformation(image, out xml, out bytes)) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (bytes < 2 || bytes > 16777216 || bytes % 2 != 0) throw new InvalidOperationException("Metadados WIM invalidos.");
        return Marshal.PtrToStringUni(xml, (int)bytes / 2).Trim('\0', '\uFEFF');
      } finally {
        if (xml != IntPtr.Zero) LocalFree(xml);
        WIMCloseHandle(image);
      }
    }
  }
}
'@
    }
    $xmlSettings = [Xml.XmlReaderSettings]::new()
    $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $xmlSettings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create([IO.StringReader]::new([DNW.WimQuery]::ReadXml($fullPath)), $xmlSettings)
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader) } finally { $reader.Dispose() }
    foreach ($image in $document.WIM.IMAGE) {
        [pscustomobject]@{
            ImageIndex = [int]$image.INDEX
            ImageName = [string]$image.NAME
            EditionId = [string]$image.WINDOWS.EDITIONID
            Architecture = [int]$image.WINDOWS.ARCH
            Build = [int]$image.WINDOWS.VERSION.BUILD
            Revision = [int]$image.WINDOWS.VERSION.SPBUILD
            UILanguage = [string]$image.WINDOWS.LANGUAGES.DEFAULT
        }
    }
}
