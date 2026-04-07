module skolemizer;

import std.stdio;
import std.file;
import std.string;
import std.algorithm.searching;

public import skolemizer.lexer;
public import skolemizer.parser;
public import skolemizer.skolemize;
public import skolemizer.model;
public import skolemizer.token;
public import skolemizer.resolve;

/// is formula satisfiable. Only works for propositional logic.
public DPLLResult isSatisfiable(string formula) {
    auto skolemized = skolemizeFormula(formula);
    auto clauses = toDisjunctForm(skolemized);
    return naiveSAT(clauses);
}

/// Skolemize a formula given as a string
public ASTNode* parseFormula(string input) {
    auto tokens = tokenize(input);
    return parse(tokens);
}

/// Skolemize a formula given as a string
public ASTNode* skolemizeFormula(string input) {
    auto tokens = tokenize(input);
    auto ast = parse(tokens);
    return skolemizeNode(ast);
}

/// Skolemize a formula given as an AST
public ASTNode* skolemizeFormula(ASTNode* ast) {
    return skolemizeNode(ast);
}

unittest {
    // Enable UTF-8 output on Windows
    version(Windows) {
        import core.sys.windows.windows : SetConsoleCP, SetConsoleOutputCP;
        SetConsoleCP(65001); // UTF-8 input
        SetConsoleOutputCP(65001); // UTF-8 output
    }

	string formula = "∀x∃y∀z∃w(P(s(x)) → (P(y) & P(w) → ¬P(s(z)))))";
	dstring skolemized = toFormulaString(skolemizeFormula(formula));
	assert(skolemized.replace(" "d, ""d) == "¬P(s(v0)) ∨ ¬P(f0(v0)) ∨ ¬P(f1(v0, v2)) ∨ ¬P(s(v2))"d.replace(" "d, ""d));

	formula = "∀x(P(x) ↔ R(x))";
	skolemized = toFormulaString(skolemizeFormula(formula));
	assert(skolemized.replace(" "d, ""d) == "¬P(v0) ∨ R(v0) & ¬R(v0) ∨ P(v0)"d.replace(" "d, ""d));

	formula = "∀x((P(x) → R(x)) & (R(x) → P(x)))";
	skolemized = toFormulaString(skolemizeFormula(formula));
	assert(skolemized.replace(" "d, ""d) == "¬P(v0) ∨ R(v0) & ¬R(v0) ∨ P(v0)"d.replace(" "d, ""d));
}