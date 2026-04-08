module skolemizer.resolve;

import skolemizer.model;
import skolemizer.parser;
import skolemizer.skolemize;

import std.stdio;
import std.format;
import std.sumtype;

// result sumtype

enum DPLLResult { Satisfiable = "Satisfiable", Unsatisfiable = "Unsatisfiable", Unknown = "Unknown" }


// https://en.wikipedia.org/wiki/DPLL_algorithm
DPLLResult DPLL(ASTNode*[hash_t][hash_t] clauses)
{
    int numTries = 0;
    while (true) {
        if (numTries > 1_000) {
            return DPLLResult.Unknown;
        }

        // look for unit clauses
        foreach (key, clause; clauses) {
            if (clause.length == 1) {
                // found a unit clause, assign the variable and simplify
                auto unit = *clause.values[0];
                writeln("Found unit clause: " ~ toFormulaString(&unit));
            }
        }

        foreach (key, clause; clauses) {
            if (clause.length == 0) {
                return DPLLResult.Unsatisfiable;
            }
        }

        numTries++;
    }
    return DPLLResult.Satisfiable;
}

public DPLLResult naiveSAT(ASTNode*[hash_t][hash_t] clauses)
{
    ASTNode*[] variables = getVariables(clauses);
    bool[] assignment = new bool[variables.length];
    assignment[0..$] = false;
    bool allSatisfied;
    do {
        allSatisfied = false;
        foreach (key, clause; clauses) {
            bool clauseSatisfied = false;
            foreach (key2, clause2; clause) {
                clauseSatisfied = clauseSatisfied || evaluateVariable(clause2, variables, assignment);
            }
            if (!clauseSatisfied) {
                allSatisfied = false;
                break;
            } else {
                allSatisfied = true;
            }
        }
    } while (increment(assignment));
    return allSatisfied ? DPLLResult.Satisfiable : DPLLResult.Unsatisfiable;
}

unittest {
    import skolemizer.lexer;
    import skolemizer.parser;

    auto tokens = tokenize("a & !a");
	auto ast = parse(tokens);
	auto skolem = skolemizeNode(ast);
    auto clauses = toDisjunctForm(skolem);

    assert(naiveSAT(clauses) == DPLLResult.Unsatisfiable);

    tokens = tokenize("a | !a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Satisfiable);

    tokens = tokenize("(a ∨ b) ∧ (¬a ∨ b) ∧ (a ∨ ¬b) ∧ (¬a ∨ ¬b)");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Unsatisfiable);

    tokens = tokenize("a ⟶ b ⟶ a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Satisfiable);

    tokens = tokenize("¬(a | ¬a)");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Unsatisfiable);

    tokens = tokenize("a ⟷ ¬a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Unsatisfiable);

    tokens = tokenize("((a ∨ ¬a) ∧ (b ∨ ¬b) ∧ (c ∨ ¬c) ∧ (d ∨ ¬d))
                        ∧ ((a ∨ b ∨ ¬a ∨ ¬b) ∧ (c ∨ d ∨ ¬c ∨ ¬d))
                        ∧ ((a ∧ b) → (a ∨ b))
                        ∧ ((c ∧ d) → (c ∨ d))
                        ∧ ((a → b) ∨ (b → a))
                        ∧ ((a ↔ a) ∧ (b ↔ b) ∧ (c ↔ c) ∧ (d ↔ d))");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Satisfiable);

    tokens = tokenize("((a ∧ ¬a) ∨ (b ∧ ¬b))
                        ∧ ((c ∧ ¬c) ∨ (d ∧ ¬d))
                        ∧ ((a ∧ ¬a) ∧ (b ∧ ¬b) ∧ (c ∧ ¬c) ∧ (d ∧ ¬d))");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == DPLLResult.Unsatisfiable);
}

private bool evaluateVariable(ASTNode* clause, ASTNode*[] variables, bool[] assignment)
{
    if (variables.length != assignment.length) {
        throw new Exception("Variables and assignment length mismatch");
    }

    if (clause.type == NodeType.Variable) {
        for (size_t i = 0; i < variables.length; ++i) {
            if (opEqualsASTNode(clause, variables[i])) {
                return assignment[i];
            }
        }
        throw new Exception("Variable not found in assignment");
    } else if (clause.type == NodeType.Negation) {
        return !evaluateVariable(clause.left, variables, assignment);
    } else if (clause.type == NodeType.Disjunction) {
        return evaluateVariable(clause.left, variables, assignment) || evaluateVariable(clause.right, variables, assignment);
    } else {
        throw new Exception("Unsupported clause type: " ~ cast(string)(clause.type));
    }
}

// Helper which increments a boolean array as if it were a binary number
private bool increment(bool[] bits) {
    for (ulong i = bits.length - 1; i >= 0; --i) {
        if (i >= bits.length) {
            return false;
        }
        if (!bits[i]) {
            bits[i] = true;
            return true;
        }
        bits[i] = false;
    }
    return false;
}

public ASTNode*[] getVariables(ASTNode*[hash_t][hash_t] clauses)
{
    ASTNode*[size_t] hashSet;
    foreach (key, clause; clauses) {
        foreach (key2, clause2; clause)
        {
            if (clause2.type == NodeType.Variable) {
                hashSet[hashOfASTNode(clause2)] = clause2;
            } else if (clause2.type == NodeType.Negation)
            {
                hashSet[hashOfASTNode(clause2.left)] = clause2.left;
            } else {
                throw new Exception("Unidentified nodetype '" ~ cast(string)(clause2.type) ~ "'");
            }
        }
    }
    ASTNode*[] result;
    foreach (key, value; hashSet) {
        result ~= value;
    }
    return result;
}



public ASTNode*[hash_t][hash_t] toDisjunctForm(ASTNode* node)
{
    node = skolemizeNode(node);
    node = distribute(node);
    
    // hashset workaround using an associative array
    ASTNode*[hash_t] clauses;
    splitOnConj(node, clauses);
    ASTNode*[hash_t][hash_t] disjunctClauses;
    foreach (hash, clause; clauses) {
        ASTNode*[hash_t] disjunctSet;
        splitOnDisj(clause, disjunctSet);
        disjunctClauses[hash] = disjunctSet;
    }
    return disjunctClauses;
}

public ASTNode* distribute(ASTNode* node) {
    if (node is null) return null;

    if (node.type == NodeType.Conjunction) {
        node.left = distribute(node.left);
        node.right = distribute(node.right);
        return node;
    }

    if (node.type == NodeType.Disjunction) {
        auto l = distribute(node.left);
        auto r = distribute(node.right);

        if (l.type == NodeType.Conjunction)
            return distribute(new ASTNode(
                NodeType.Conjunction,
                null,
                distribute(new ASTNode(NodeType.Disjunction, null, l.left, cloneAST(r))),
                distribute(new ASTNode(NodeType.Disjunction, null, l.right, cloneAST(r)))
            ));

        if (r.type == NodeType.Conjunction)
            return distribute(new ASTNode(
                NodeType.Conjunction,
                null,
                distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.left)),
                distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.right))
            ));

        node.left = l;
        node.right = r;
        return node;
    }

    return node;
}

private void splitOnDisj(ASTNode* node, ref ASTNode*[hash_t] disjuncts)
{
    if (node is null) return;

    if (node.type == NodeType.Disjunction) {
        splitOnDisj(node.left, disjuncts);
        splitOnDisj(node.right, disjuncts);
    } else {
        auto hash = hashOfASTNode(node);
        disjuncts[hash] = node;
    }
}

private void splitOnConj(ASTNode* node, ref ASTNode*[hash_t] clauses)
{
    if (node is null) return;

    if (node.type == NodeType.Conjunction) {
        splitOnConj(node.left, clauses);
        splitOnConj(node.right, clauses);
    } else {
        auto hash = hashOfASTNode(node);
        clauses[hash] = node;
    }
}

dstring toSetString(ASTNode*[hash_t][hash_t] set)
{
	dstring result;
	result ~= "{\n";
	foreach (key, value; set) {
        result ~= "\t{\n";
        result ~= "\t\t";
		foreach (clause; value) {
			result ~= toFormulaString(clause) ~ ", ";
		}
        // remove trailing comma and newline
        if (result.length >= 2) {
            result = result[0 .. $ - 2];
        }
        result ~= "\n\t}\n";
	}
	result ~= "}";
	return result;
}

unittest
{

}
