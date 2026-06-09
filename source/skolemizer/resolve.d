module skolemizer.resolve;

import skolemizer.model;
import skolemizer.parser;
import skolemizer.skolemize;

import std.stdio;
import std.format;
import std.sumtype;
import std.algorithm;
import std.array;
import std.conv : to;

enum SatResult
{
    Satisfiable = "Satisfiable",
    Unsatisfiable = "Unsatisfiable",
    Unknown = "Unknown"
}

// Hashmap of substitutions: variable name: ASTNode
alias Substitution = ASTNode*[dstring];

private ASTNode* walkSubst(ASTNode* node, Substitution subst)
{
    while (node !is null && node.type == NodeType.Variable)
    {
        auto p = node.value in subst;
        if (p is null)
            break;
        node = *p;
    }
    return node;
}

private bool occursIn(dstring varName, ASTNode* node, Substitution subst)
{
    node = walkSubst(node, subst);
    if (node is null)
        return false;
    if (node.type == NodeType.Variable)
        return node.value == varName;

    foreach (arg; node.args)
        if (occursIn(varName, arg, subst))
            return true;

    if (occursIn(varName, node.left, subst))
        return true;
    if (occursIn(varName, node.right, subst))
        return true;
    return false;
}

private struct MaybeSubst
{
    bool ok;
    Substitution val;
}

// Robinson's unification algorithm
private MaybeSubst unifyNodes(ASTNode* a, ASTNode* b, Substitution subst,
    bool inArgs = false)
{
    a = walkSubst(a, subst);
    b = walkSubst(b, subst);

    if (a is null && b is null)
        return MaybeSubst(true, subst);
    if (a is null || b is null)
        return MaybeSubst(false);

    if (a.type == NodeType.Variable && b.type == NodeType.Variable && a.value == b.value)
        return MaybeSubst(true, subst);

    if (a.type == NodeType.Variable)
    {
        if (!inArgs)
            return MaybeSubst(false);
        if (occursIn(a.value, b, subst))
            return MaybeSubst(false);
        Substitution s = subst.dup;
        s[a.value] = b;
        return MaybeSubst(true, s);
    }

    if (b.type == NodeType.Variable)
    {
        if (!inArgs)
            return MaybeSubst(false);
        if (occursIn(b.value, a, subst))
            return MaybeSubst(false);
        Substitution s = subst.dup;
        s[b.value] = a;
        return MaybeSubst(true, s);
    }

    if (a.type == NodeType.Constant)
    {
        if (b.type != NodeType.Constant)
            return MaybeSubst(false);
        return (a.value == b.value) ? MaybeSubst(true, subst) : MaybeSubst(false);
    }

    if (a.type != b.type)
        return MaybeSubst(false);
    if (a.value != b.value)
        return MaybeSubst(false);
    if (a.args.length != b.args.length)
        return MaybeSubst(false);

    Substitution s = subst.dup;

    foreach (i; 0 .. a.args.length)
    {
        auto r = unifyNodes(a.args[i], b.args[i], s, true);
        if (!r.ok)
            return MaybeSubst(false);
        s = r.val;
    }

    if (a.left !is null || b.left !is null)
    {
        auto r = unifyNodes(a.left, b.left, s, false);
        if (!r.ok)
            return MaybeSubst(false);
        s = r.val;
    }
    if (a.right !is null || b.right !is null)
    {
        auto r = unifyNodes(a.right, b.right, s, false);
        if (!r.ok)
            return MaybeSubst(false);
        s = r.val;
    }

    return MaybeSubst(true, s);
}

private ASTNode* applySubst(ASTNode* node, Substitution subst)
{
    if (node is null)
        return null;
    node = walkSubst(node, subst);
    if (node is null)
        return null;

    if (node.type == NodeType.Variable)
    {
        return new ASTNode(NodeType.Variable, node.value);
    }

    auto result = new ASTNode(node.type, node.value);
    result.left = applySubst(node.left, subst);
    result.right = applySubst(node.right, subst);
    result.args = node.args.map!(a => applySubst(a, subst)).array;
    return result;
}

private int _renameCounter = 0;

private ASTNode* renameVarsInNode(ASTNode* node, ref dstring[dstring] varMap, int counter, bool inArgs = false)
{
    if (node is null)
        return null;

    if (node.type == NodeType.Variable)
    {
        if (!inArgs)
            return new ASTNode(NodeType.Variable, node.value);
        if (!(node.value in varMap))
            varMap[node.value] = node.value ~ "_r"d ~ to!dstring(counter);
        return new ASTNode(NodeType.Variable, varMap[node.value]);
    }

    auto result = new ASTNode(node.type, node.value);
    result.left = renameVarsInNode(node.left, varMap, counter, false);
    result.right = renameVarsInNode(node.right, varMap, counter, false);
    result.args = node.args.map!(a => renameVarsInNode(a, varMap, counter, true)).array;
    return result;
}

private ASTNode*[hash_t] renameClauseVars(ASTNode*[hash_t] clause)
{
    int counter = ++_renameCounter;
    dstring[dstring] varMap;
    ASTNode*[hash_t] result;
    foreach (key, lit; clause)
    {
        auto renamed = renameVarsInNode(lit, varMap, counter);
        result[hashOfASTNode(renamed)] = renamed;
    }
    return result;
}

private ASTNode* getHead(ASTNode*[hash_t] clause)
{
    foreach (node; clause)
        if (isPositiveLiteral(node))
            return node;
    return null;
}

private ASTNode*[] getBody(ASTNode*[hash_t] clause)
{
    ASTNode*[] bodyNodes;
    foreach (node; clause)
        if (isNegativeLiteral(node))
            bodyNodes ~= node;
    return bodyNodes;
}

// hard limit on recursion depth to prevent infinite loops
enum int SLD_MAX_DEPTH = 2048;

public SatResult SLDResolve(ASTNode*[hash_t][hash_t] clauses)
{
    if (!checkHornClause(clauses))
        throw new Exception("Clauses must be in Horn form for SLD resolution");

    ASTNode*[hash_t][hash_t] facts;
    ASTNode*[hash_t][hash_t] rules;
    ASTNode*[hash_t][hash_t] goals;

    foreach (key, clause; clauses)
    {
        if (isFactClause(clause))
            facts[key] = clause;
        else if (isRuleClause(clause))
            rules[key] = clause;
        else if (isGoalClause(clause))
            goals[key] = clause;
        else
            throw new Exception("Clause is not a fact, rule, or goal: " ~ cast(string) toSetString(clause));
    }

    foreach (goalKey, initialGoal; goals)
    {
        ASTNode*[] positiveGoal;
        foreach (k, node; initialGoal)
            if (node.type == NodeType.Negation)
                positiveGoal ~= node.left;

        if (dfsSolve(positiveGoal, facts, rules, 0))
            return SatResult.Unsatisfiable;
    }
    return SatResult.Satisfiable;
}

private bool dfsSolve(ASTNode*[] currentGoal, ASTNode*[hash_t][hash_t] facts, ASTNode*[hash_t][hash_t] rules, int depth)
{
    if (currentGoal.length == 0)
        return true;
    if (depth >= SLD_MAX_DEPTH)
        return false;

    auto target = currentGoal[0];
    auto rest = currentGoal[1 .. $];

    foreach (fKey, fact; facts)
    {
        auto freshFact = renameClauseVars(fact);
        auto factHead = getHead(freshFact);
        if (factHead is null)
            continue;

        Substitution emptySubst;
        auto r = unifyNodes(target, factHead, emptySubst);
        if (!r.ok)
            continue;

        auto nextGoal = rest.map!(g => applySubst(g, r.val)).array;
        if (dfsSolve(nextGoal, facts, rules, depth + 1))
            return true;
    }

    foreach (rKey, rule; rules)
    {
        auto freshRule = renameClauseVars(rule);
        auto ruleHead = getHead(freshRule);
        if (ruleHead is null)
            continue;

        Substitution emptySubst;
        auto r = unifyNodes(target, ruleHead, emptySubst);
        if (!r.ok)
            continue;

        auto nextGoal = rest.map!(g => applySubst(g, r.val)).array;
        foreach (lit; getBody(freshRule))
            nextGoal ~= applySubst(lit.left, r.val);

        if (dfsSolve(nextGoal, facts, rules, depth + 1))
            return true;
    }

    return false;
}

public ASTNode*[hash_t][hash_t] tryHornConvert(ASTNode*[hash_t][hash_t] clauses)
{
    if (checkHornClause(clauses))
        return clauses;

    ASTNode*[hash_t][hash_t] modifiedClauses = clauses.dup;
    foreach (key, clause; modifiedClauses)
    {
        foreach (key2, literal; clause)
        {
            if (isPositiveLiteral(literal))
                clause[key2] = new ASTNode(NodeType.Negation, null, literal);
            else if (literal.type == NodeType.Negation)
                clause[key2] = literal.left;
        }
        if (checkHornClause(modifiedClauses))
            return modifiedClauses;
    }

    throw new Exception("Unable to convert clauses to Horn form");
}

public bool isFactClause(ASTNode*[hash_t] clause)
{
    int pos, neg;
    foreach (key, d; clause)
    {
        if (isPositiveLiteral(d))
            pos++;
        else if (d.type == NodeType.Negation)
            neg++;
        else
            throw new Exception("Unsupported node type: " ~ cast(string)(d.type));
    }
    return pos == 1 && neg == 0;
}

public bool isRuleClause(ASTNode*[hash_t] clause)
{
    int pos, neg;
    foreach (key, d; clause)
    {
        if (isPositiveLiteral(d))
            pos++;
        else if (d.type == NodeType.Negation)
            neg++;
        else
            throw new Exception("Unsupported node type: " ~ cast(string)(d.type));
    }
    return pos == 1 && neg > 0;
}

public bool isGoalClause(ASTNode*[hash_t] clause)
{
    int pos, neg;
    foreach (key, d; clause)
    {
        if (isPositiveLiteral(d))
            pos++;
        else if (d.type == NodeType.Negation)
            neg++;
        else
            throw new Exception("Unsupported node type: " ~ cast(string)(d.type));
    }
    return pos == 0 && neg > 0;
}

public bool isPositiveLiteral(ASTNode* node)
{
    return node.type == NodeType.Variable || node.type == NodeType.Predicate;
}

public bool isNegativeLiteral(ASTNode* node)
{
    return node.type == NodeType.Negation && isPositiveLiteral(node.left);
}

public bool checkHornClause(ASTNode* clause)
{
    auto cnf = toDisjunctForm(clause);
    foreach (key, disjuncts; cnf)
    {
        int numPositive;
        foreach (variable, disjunct; disjuncts)
        {
            if (isPositiveLiteral(disjunct))
                numPositive++;
            else if (disjunct.type == NodeType.Negation)
            {
            }
            else
                throw new Exception("Unsupported node type: " ~ cast(string)(disjunct.type));
        }
        if (numPositive > 1)
            return false;
    }
    return true;
}

public bool checkHornClause(ASTNode*[hash_t][hash_t] clauses)
{
    foreach (key, disjuncts; clauses)
    {
        int numPositive;
        foreach (variable, disjunct; disjuncts)
        {
            if (isPositiveLiteral(disjunct))
                numPositive++;
            else if (disjunct.type == NodeType.Negation)
            {
            }
            else
                throw new Exception("Unsupported node type: " ~ cast(string)(disjunct.type));
        }
        if (numPositive > 1)
            return false;
    }
    return true;
}

public bool checkHornClause(string formula)
{
    auto ast = parseFormula(formula);
    return checkHornClause(ast);
}

// Naive SAT

public SatResult naiveSAT(ASTNode*[hash_t][hash_t] clauses)
{
    ASTNode*[] variables = getVariables(clauses);
    bool[] assignment = new bool[variables.length];
    assignment[0 .. $] = false;
    bool allSatisfied;
    do
    {
        allSatisfied = false;
        foreach (key, clause; clauses)
        {
            bool clauseSatisfied = false;
            foreach (key2, clause2; clause)
                clauseSatisfied = clauseSatisfied || evaluateVariable(clause2, variables, assignment);
            if (!clauseSatisfied)
            {
                allSatisfied = false;
                break;
            }
            else
                allSatisfied = true;
        }
        if (allSatisfied)
            return SatResult.Satisfiable;
    }
    while (increment(assignment));
    return SatResult.Unsatisfiable;
}

unittest
{
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

// debug
unittest
{
    // P(a) vs P(b) two distinct constants which should not unify
    {
        auto Pa = new ASTNode(NodeType.Predicate, "P"d);
        Pa.args ~= new ASTNode(NodeType.Constant, "a"d);
        auto Pb = new ASTNode(NodeType.Predicate, "P"d);
        Pb.args ~= new ASTNode(NodeType.Constant, "b"d);
        Substitution s;
        assert(!unifyNodes(Pa, Pb, s).ok);
    }

    // P(a) vs P(x) {x ← a}
    {
        auto Pa = new ASTNode(NodeType.Predicate, "P"d);
        Pa.args ~= new ASTNode(NodeType.Constant, "a"d);
        auto Px = new ASTNode(NodeType.Predicate, "P"d);
        Px.args ~= new ASTNode(NodeType.Variable, "x"d);
        Substitution s;
        auto r = unifyNodes(Pa, Px, s);
        assert(r.ok);
        assert("x"d in r.val);
        auto bound = applySubst(new ASTNode(NodeType.Variable, "x"d), r.val);
        assert(bound.type == NodeType.Constant && bound.value == "a"d);
    }

    // P(x) vs P(x) must unify without new bindings
    {
        auto Px1 = new ASTNode(NodeType.Predicate, "P"d);
        Px1.args ~= new ASTNode(NodeType.Variable, "x"d);
        auto Px2 = new ASTNode(NodeType.Predicate, "P"d);
        Px2.args ~= new ASTNode(NodeType.Variable, "x"d);
        Substitution s;
        auto r = unifyNodes(Px1, Px2, s);
        assert(r.ok);
        assert(r.val.length == 0);
    }

    {
        auto p1 = new ASTNode(NodeType.Variable, "p"d);
        auto p2 = new ASTNode(NodeType.Variable, "p"d);
        Substitution s;
        auto r = unifyNodes(p1, p2, s);
        assert(r.ok);
        assert(r.val.length == 0);
    }

    {
        auto p = new ASTNode(NodeType.Variable, "p"d);
        auto q = new ASTNode(NodeType.Variable, "q"d);
        Substitution s;
        assert(!unifyNodes(p, q, s).ok);
    }

    {
        auto Qa = new ASTNode(NodeType.Predicate, "Q"d);
        Qa.args ~= new ASTNode(NodeType.Constant, "a"d);
        auto Pa = new ASTNode(NodeType.Predicate, "P"d);
        Pa.args ~= new ASTNode(NodeType.Constant, "a"d);
        Substitution s;
        assert(!unifyNodes(Qa, Pa, s).ok);
    }
}


private bool evaluateVariable(ASTNode* clause, ASTNode*[] variables, bool[] assignment)
{
    if (variables.length != assignment.length)
        throw new Exception("Variables and assignment length mismatch");

    if (isPositiveLiteral(clause))
    {
        for (size_t i = 0; i < variables.length; ++i)
            if (opEqualsASTNode(clause, variables[i]))
                return assignment[i];
        throw new Exception("Variable/predicate not found in assignment");
    }
    else if (clause.type == NodeType.Negation)
    {
        return !evaluateVariable(clause.left, variables, assignment);
    }
    else if (clause.type == NodeType.Disjunction)
    {
        return evaluateVariable(clause.left, variables, assignment)
            || evaluateVariable(clause.right, variables, assignment);
    }
    else
    {
        throw new Exception("Unsupported clause type: " ~ cast(string)(clause.type));
    }
}

private bool increment(bool[] bits)
{
    for (ulong i = bits.length - 1; i >= 0; --i)
    {
        if (i >= bits.length)
            return false;
        if (!bits[i])
        {
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
    foreach (key, clause; clauses)
        foreach (key2, clause2; clause)
        {
            if (isPositiveLiteral(clause2))
                hashSet[hashOfASTNode(clause2)] = clause2;
            else if (clause2.type == NodeType.Negation)
                hashSet[hashOfASTNode(clause2.left)] = clause2.left;
            else
                throw new Exception("Unidentified nodetype '" ~ cast(string)(clause2.type) ~ "'");
        }
    ASTNode*[] result;
    foreach (key, value; hashSet)
        result ~= value;
    return result;
}

private ASTNode*[hash_t] copyGoal(ASTNode*[hash_t] goal)
{
    ASTNode*[hash_t] newGoal;
    foreach (k, v; goal)
        newGoal[k] = v;
    return newGoal;
}

public ASTNode*[hash_t][hash_t] toDisjunctForm(ASTNode* node)
{
    node = skolemizeNode(node);
    node = distribute(node);

    ASTNode*[hash_t] clauses;
    splitOnConj(node, clauses);
    ASTNode*[hash_t][hash_t] disjunctClauses;
    foreach (hash, clause; clauses)
    {
        ASTNode*[hash_t] disjunctSet;
        splitOnDisj(clause, disjunctSet);
        disjunctClauses[hash] = disjunctSet;
    }
    return disjunctClauses;
}

public ASTNode*[hash_t][hash_t] toDisjunctForm(string formula)
{
    auto ast = parseFormula(formula);
    return toDisjunctForm(ast);
}

public ASTNode* distribute(ASTNode* node)
{
    if (node is null)
        return null;

    if (node.type == NodeType.Conjunction)
    {
        node.left = distribute(node.left);
        node.right = distribute(node.right);
        return node;
    }

    if (node.type == NodeType.Disjunction)
    {
        auto l = distribute(node.left);
        auto r = distribute(node.right);

        if (l.type == NodeType.Conjunction)
            return distribute(new ASTNode(NodeType.Conjunction, null,
                    distribute(new ASTNode(NodeType.Disjunction, null, l.left, cloneAST(r))),
                    distribute(new ASTNode(NodeType.Disjunction, null, l.right, cloneAST(r)))));

        if (r.type == NodeType.Conjunction)
            return distribute(new ASTNode(NodeType.Conjunction, null,
                    distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.left)),
                    distribute(new ASTNode(NodeType.Disjunction, null, cloneAST(l), r.right))));

        node.left = l;
        node.right = r;
        return node;
    }

    return node;
}

private void splitOnDisj(ASTNode* node, ref ASTNode*[hash_t] disjuncts)
{
    if (node is null)
        return;
    if (node.type == NodeType.Disjunction)
    {
        splitOnDisj(node.left, disjuncts);
        splitOnDisj(node.right, disjuncts);
    }
    else
    {
        disjuncts[hashOfASTNode(node)] = node;
    }
}

private void splitOnConj(ASTNode* node, ref ASTNode*[hash_t] clauses)
{
    if (node is null)
        return;
    if (node.type == NodeType.Conjunction)
    {
        splitOnConj(node.left, clauses);
        splitOnConj(node.right, clauses);
    }
    else
    {
        clauses[hashOfASTNode(node)] = node;
    }
}

dstring toSetString(ASTNode*[hash_t][hash_t] set)
{
    dstring result = "{\n";
    foreach (key, value; set)
    {
        result ~= "\t{\n\t\t";
        foreach (clause; value)
            result ~= toFormulaString(clause) ~ ", ";
        if (result.length >= 2)
            result = result[0 .. $ - 2];
        result ~= "\n\t}\n";
    }
    result ~= "}";
    return result;
}

dstring toSetString(ASTNode*[hash_t] set)
{
    dstring result = "{\n";
    foreach (key, value; set)
        result ~= "\t" ~ toFormulaString(value) ~ ",\n";
    if (result.length >= 2)
        result = result[0 .. $ - 2];
    result ~= "\n}";
    return result;
}

unittest
{

}
