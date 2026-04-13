module skolemizer.resolve;

import skolemizer.model;
import skolemizer.parser;
import skolemizer.skolemize;

import std.stdio;
import std.format;
import std.sumtype;

// result sumtype

enum SatResult { Satisfiable = "Satisfiable", Unsatisfiable = "Unsatisfiable", Unknown = "Unknown" }


SatResult SLDResolve(ASTNode*[hash_t][hash_t] clauses)
{
    if (!checkHornClause(clauses)) {
        throw new Exception("Clauses must be in Horn form for SLD resolution");
    }

    ASTNode*[hash_t][hash_t] facts;
    ASTNode*[hash_t][hash_t] rules;
    ASTNode*[hash_t][hash_t] goals;
    
    foreach (key, clause; clauses) {
        if (isFactClause(clause)) {
            facts[key] = clause;
        } else if (isRuleClause(clause)) {
            rules[key] = clause;
        } else if (isGoalClause(clause)) {
            goals[key] = clause;
        } else {
            throw new Exception("Clause is not a fact, rule, or goal: " ~ cast(string) toSetString(clause));
        }
    }

    foreach (goalKey, initialGoal; goals) {
        ASTNode*[hash_t] positiveGoal;
        foreach (k, node; initialGoal) {
            if (node.type == NodeType.Negation) {
                auto inner = node.left;
                positiveGoal[hashOfASTNode(inner)] = inner;
            }
        }
        if (dfsSolve(positiveGoal, facts, rules)) {
            return SatResult.Unsatisfiable;
        }
    }
    return SatResult.Satisfiable;
}

bool dfsSolve(ASTNode*[hash_t] currentGoal, 
              ASTNode*[hash_t][hash_t] facts, 
              ASTNode*[hash_t][hash_t] rules) 
{
    if (currentGoal.length == 0) return true;

    auto targetLiteral = currentGoal.keys[0]; 

    foreach (fKey, fact; facts) {
        if (matches(fact, targetLiteral)) {
            auto nextGoal = copyGoal(currentGoal);
            nextGoal.remove(targetLiteral); // resolved
            if (dfsSolve(nextGoal, facts, rules)) return true;
        }
    }

    foreach (rKey, rule; rules) {
        if (matchesHead(rule, targetLiteral)) {
            auto nextGoal = copyGoal(currentGoal);
            nextGoal.remove(targetLiteral);
            
            foreach (lit; getBody(rule)) {
                auto inner = lit.left;
                nextGoal[hashOfASTNode(inner)] = inner;
            }
            
            if (dfsSolve(nextGoal, facts, rules)) return true;
        }
    }

    return false;
}

bool matches(ASTNode*[hash_t] fact, hash_t targetLiteralHash) {
    foreach (node; fact) {
        if (isPositiveLiteral(node)) {
            return hashOfASTNode(node) == targetLiteralHash;
        }
    }
    return false;
}

bool matchesHead(ASTNode*[hash_t] rule, hash_t targetLiteralHash) {
    foreach (node; rule) {
        if (isPositiveLiteral(node)) {
            return hashOfASTNode(node) == targetLiteralHash;
        }
    }
    return false;
}

ASTNode*[] getBody(ASTNode*[hash_t] rule) {
    ASTNode*[] bodyNodes;
    foreach (node; rule) {
        if (isNegativeLiteral(node)) {
            bodyNodes ~= node;
        }
    }
    return bodyNodes;
}

ASTNode*[hash_t] copyGoal(ASTNode*[hash_t] goal) {
    ASTNode*[hash_t] newGoal;
    foreach (k, v; goal) {
        newGoal[k] = v;
    }
    return newGoal;
}

// public ASTNode*[hash_t][hash_t] tryHornConvert(ASTNode* node)

// if a set of clauses isn't in horn form, loop through every clause and negate every literal until it is or until we've tried everything.
public ASTNode*[hash_t][hash_t] tryHornConvert(ASTNode*[hash_t][hash_t] clauses)
{
    if (checkHornClause(clauses)) {
        return clauses;
    }

    ASTNode*[hash_t][hash_t] modifiedClauses = clauses.dup;
    foreach (key, clause; modifiedClauses) {
        foreach (key2, literal; clause) {
            if (literal.type == NodeType.Variable) {
                clause[key2] = new ASTNode(NodeType.Negation, null, literal);
            } else if (literal.type == NodeType.Negation) {
                clause[key2] = literal.left;
            }
        }
        if (checkHornClause(modifiedClauses)) {
            return modifiedClauses;
        }
    }

    throw new Exception("Unable to convert clauses to Horn form");
}

public bool isFactClause(ASTNode*[hash_t] clause)
{
    int numPositiveLiterals = 0;
    int numNegativeLiterals = 0;
    foreach (key, disjunct; clause) {
        if (disjunct.type == NodeType.Variable) {
            numPositiveLiterals++;
        } else if (disjunct.type == NodeType.Negation) {
            numNegativeLiterals++;
        } else {
            throw new Exception("Unsupported node type in disjunct: " ~ cast(string)(disjunct.type));
        }
    }
    return numPositiveLiterals == 1 && numNegativeLiterals == 0;
}

public bool isRuleClause(ASTNode*[hash_t] clause)
{
    int numPositiveLiterals = 0;
    int numNegativeLiterals = 0;
    foreach (key, disjunct; clause) {
        if (disjunct.type == NodeType.Variable) {
            numPositiveLiterals++;
        } else if (disjunct.type == NodeType.Negation) {
            numNegativeLiterals++;
        } else {
            throw new Exception("Unsupported node type in disjunct: " ~ cast(string)(disjunct.type));
        }
    }
    return numPositiveLiterals == 1 && numNegativeLiterals > 0;
}

public bool isGoalClause(ASTNode*[hash_t] clause)
{
    int numPositiveLiterals = 0;
    int numNegativeLiterals = 0;
    foreach (key, disjunct; clause) {
        if (disjunct.type == NodeType.Variable) {
            numPositiveLiterals++;
        } else if (disjunct.type == NodeType.Negation) {
            numNegativeLiterals++;
        } else {
            throw new Exception("Unsupported node type in disjunct: " ~ cast(string)(disjunct.type));
        }
    }
    return numPositiveLiterals == 0 && numNegativeLiterals > 0;
}

public bool isPositiveLiteral(ASTNode* node)
{
    return node.type == NodeType.Variable;
}

public bool isNegativeLiteral(ASTNode* node)
{
    return node.type == NodeType.Negation && node.left.type == NodeType.Variable;
}

public bool checkHornClause(ASTNode* clause)
{
    // ¬((a&b⟶c)⟶(a&c⟶d)⟶(b&d⟶e)⟶a&b⟶e)
    auto cnf = toDisjunctForm(clause);
    foreach (key, disjuncts; cnf) {
        int numPositiveLiterals = 0;
        foreach (variable, disjunct; disjuncts) {
            if (disjunct.type == NodeType.Variable) {
                numPositiveLiterals++;
            } else if (disjunct.type == NodeType.Negation) {
                // explicicity
            } else {
                throw new Exception("Unsupported node type in disjunct: " ~ cast(string)(disjunct.type));
            }
        }
        if (numPositiveLiterals > 1) {
            return false;
        }
    }

    return true;
}

public bool checkHornClause(ASTNode*[hash_t][hash_t] clauses)
{
    foreach (key, disjuncts; clauses) {
        int numPositiveLiterals = 0;
        foreach (variable, disjunct; disjuncts) {
            if (disjunct.type == NodeType.Variable) {
                numPositiveLiterals++;
            } else if (disjunct.type == NodeType.Negation) {
                // explicicity
            } else {
                throw new Exception("Unsupported node type in disjunct: " ~ cast(string)(disjunct.type));
            }
        }
        if (numPositiveLiterals > 1) {
            return false;
        }
    }

    return true;
}

// Ditto
public bool checkHornClause(string formula)
{
    auto ast = parseFormula(formula);
    return checkHornClause(ast);
}

public SatResult naiveSAT(ASTNode*[hash_t][hash_t] clauses)
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
        if (allSatisfied) return SatResult.Satisfiable;
    } while (increment(assignment));
    return SatResult.Unsatisfiable;
}

unittest {
    import skolemizer.lexer;
    import skolemizer.parser;

    auto tokens = tokenize("a & !a");
	auto ast = parse(tokens);
	auto skolem = skolemizeNode(ast);
    auto clauses = toDisjunctForm(skolem);

    assert(naiveSAT(clauses) == SatResult.Unsatisfiable);

    tokens = tokenize("a | !a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Satisfiable);

    tokens = tokenize("(a ∨ b) ∧ (¬a ∨ b) ∧ (a ∨ ¬b) ∧ (¬a ∨ ¬b)");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Unsatisfiable);

    tokens = tokenize("a ⟶ b ⟶ a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Satisfiable);

    tokens = tokenize("¬(a | ¬a)");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Unsatisfiable);

    tokens = tokenize("a ⟷ ¬a");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Unsatisfiable);

    tokens = tokenize("((a ∨ ¬a) ∧ (b ∨ ¬b) ∧ (c ∨ ¬c) ∧ (d ∨ ¬d))
                        ∧ ((a ∨ b ∨ ¬a ∨ ¬b) ∧ (c ∨ d ∨ ¬c ∨ ¬d))
                        ∧ ((a ∧ b) → (a ∨ b))
                        ∧ ((c ∧ d) → (c ∨ d))
                        ∧ ((a → b) ∨ (b → a))
                        ∧ ((a ↔ a) ∧ (b ↔ b) ∧ (c ↔ c) ∧ (d ↔ d))");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Satisfiable);

    tokens = tokenize("((a ∧ ¬a) ∨ (b ∧ ¬b))
                        ∧ ((c ∧ ¬c) ∨ (d ∧ ¬d))
                        ∧ ((a ∧ ¬a) ∧ (b ∧ ¬b) ∧ (c ∧ ¬c) ∧ (d ∧ ¬d))");
    ast = parse(tokens);
    skolem = skolemizeNode(ast);
    clauses = toDisjunctForm(skolem);
    assert(naiveSAT(clauses) == SatResult.Unsatisfiable);
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

// Ditto
public ASTNode*[hash_t][hash_t] toDisjunctForm(string formula)
{
    auto ast = parseFormula(formula);
    return toDisjunctForm(ast);
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

dstring toSetString(ASTNode*[hash_t] set)
{
    dstring result;
    result ~= "{\n";
    foreach (key, value; set) {
        result ~= "\t" ~ toFormulaString(value) ~ ",\n";
    }
    // remove trailing comma and newline
    if (result.length >= 2) {
        result = result[0 .. $ - 2];
    }
    result ~= "\n}";
    return result;
}

unittest
{

}
