import Foundation

/// Procura repositórios git abaixo de uma pasta raiz, sem descer dentro de um repositório já encontrado.
public enum RepoFinder {
    static let skippedFolders: Set<String> = [
        "node_modules", "vendor", "Pods", "build", "dist", "DerivedData", "Library",
    ]

    public static func find(in root: URL, maxDepth: Int = 4) -> [URL] {
        var found: [URL] = []
        walk(canonical(root), depth: 0, maxDepth: maxDepth, into: &found)
        return found.sorted { $0.path < $1.path }
    }

    /// Caminho real, sem links (ex: `/var` → `/private/var`), para o mesmo repo ter sempre a mesma chave.
    public static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    private static func walk(_ dir: URL, depth: Int, maxDepth: Int, into found: inout [URL]) {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            found.append(dir)
            return
        }
        guard depth < maxDepth,
              let children = try? fm.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }

        for child in children where !skippedFolders.contains(child.lastPathComponent) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &found)
        }
    }
}
