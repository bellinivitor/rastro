import Testing
@testable import RastroCore

struct CommitMessageTests {
    @Test(arguments: [
        ("feat: timeline por dia", "feat", "Timeline por dia"),
        ("FEAT: Adicionados códigos", "feat", "Adicionados códigos"),
        ("REFACTOR: Ajustado layout", "refactor", "Ajustado layout"),
        ("fix(api)!: corrige token", "fix", "Corrige token"),
        ("[BUGFIX] Aba SCCO", "fix", "Aba SCCO"),
        ("[feat]: nova tela", "feat", "Nova tela"),
        ("chore:sem espaço", "chore", "Sem espaço"),
    ])
    func parsesType(subject: String, type: String, text: String) {
        #expect(CommitMessage.parse(subject) == CommitMessage(type: type, text: text))
    }

    @Test(arguments: [
        "Remove a tela de cobertura",
        "Importação do eDNE: tela de endereço",
        "[WIP-123] algo",
        "Merge: x",
        "feat:",
        "",
    ])
    func keepsSubjectWithoutKnownType(subject: String) {
        #expect(CommitMessage.parse(subject) == CommitMessage(type: nil, text: subject))
    }

    @Test func splitsItemsJoinedWithDash() {
        let message = CommitMessage.parse("REFACTOR: Ajustado layout - Corrigido tamanho -  - Removido estado")
        #expect(message.headline == "Ajustado layout")
        #expect(message.details == ["Corrigido tamanho", "Removido estado"])
        #expect(CommitMessage.parse("Remove tela").details.isEmpty)
        #expect(CommitMessage.parse("Remove tela").headline == "Remove tela")
    }
}
