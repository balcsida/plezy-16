// Checks the compiled host, not generated source text or a mocked registrar.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

if (args.Length != 1) throw new ArgumentException("Expected an inspected TPK path");
using var archive = ZipFile.OpenRead(args[0]);
using var hostStream = archive.GetEntry("bin/Runner.dll").Open();
using var hostBytes = new MemoryStream();
hostStream.CopyTo(hostBytes);
hostBytes.Position = 0;
using var pe = new PEReader(hostBytes);
var metadata = pe.GetMetadataReader();
var imports = new HashSet<string>(StringComparer.Ordinal);
foreach (var handle in metadata.MethodDefinitions)
{
    var import = metadata.GetMethodDefinition(handle).GetImport();
    if (import.Module.IsNil) continue;
    var module = metadata.GetString(metadata.GetModuleReference(import.Module).Name);
    if (module == "flutter_plugins.so" || module == "libflutter_plugins.so")
        imports.Add(metadata.GetString(import.Name));
}
if (imports.Count == 0) throw new Exception("Plezy host has no native plugin imports to verify");

var directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "plezy-plugin-imports-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(directory);
try
{
    var library = System.IO.Path.Combine(directory, "libflutter_plugins.so");
    archive.GetEntry("lib/libflutter_plugins.so").ExtractToFile(library);
    var start = new ProcessStartInfo("readelf") { RedirectStandardOutput = true, UseShellExecute = false };
    foreach (var argument in new[] { "--dyn-syms", "--wide", "--", library }) start.ArgumentList.Add(argument);
    using var process = Process.Start(start);
    var output = process.StandardOutput.ReadToEnd();
    process.WaitForExit();
    if (process.ExitCode != 0) throw new Exception("Could not read packaged native exports");
    var exports = new HashSet<string>(StringComparer.Ordinal);
    foreach (var line in output.Split('\n'))
    {
        var columns = line.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
        if (columns.Length >= 8 && columns[3] == "FUNC" && columns[6] != "UND" &&
            (columns[4] == "GLOBAL" || columns[4] == "WEAK") &&
            (columns[5] == "DEFAULT" || columns[5] == "PROTECTED"))
            exports.Add(columns[7]);
    }
    var missing = imports.Except(exports).OrderBy(name => name).ToArray();
    if (missing.Length != 0)
    {
        Console.Error.WriteLine("Host imports missing from libflutter_plugins.so: " + string.Join(", ", missing));
        return 1;
    }
    Console.WriteLine("Packaged native plugin imports verified: " + imports.Count);
}
finally
{
    Directory.Delete(directory, recursive: true); // Only this test's unique temporary directory.
}
return 0;
