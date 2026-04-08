module skolemizer.skolemize;

import std.stdio;
import std.format;
import std.utf;
import std.typecons;

import skolemizer.model;
import skolemizer.parser;


public ASTNode* skolemizeNode(ASTNode* node)
{
    node = removeImplication(node);
    node = removeBiconditional(node);
    node = negationsInward(node);
    node = standardizeVariables(node);
    node = moveQuantifiersToFront(node);
    node = eliminateExistentialQuantifiers(node);
    return node;
}

/// Turn A -> B into !A | B
public ASTNode* removeImplication(ASTNode* node)
{
    if (node is null) return null;

    node.left  = removeImplication(node.left);
    node.right = removeImplication(node.right);

    if (node.type == NodeType.Implication) {
        ASTNode* negated = new ASTNode(NodeType.Negation, ""d, node.left, null);
        node.type  = NodeType.Disjunction;
        node.left  = negated;
    }

    return node;
}

/// Turn A <-> B into (A -> B) & (B -> A)
public ASTNode* removeBiconditional(ASTNode* node)
{
    if (node is null) return null;

    node.left  = removeBiconditional(node.left);
    node.right = removeBiconditional(node.right);

    if (node.type == NodeType.Biconditional) {
        ASTNode* leftImplication  = new ASTNode(NodeType.Implication, ""d, node.left, node.right);
        ASTNode* rightImplication = new ASTNode(NodeType.Implication, ""d, node.right, node.left);
        node.type  = NodeType.Conjunction;
        node.left  = leftImplication;
        node.right = rightImplication;
    }

    return node;
}

/*
 * !!A into A
 * !(A&B) into !A | !B
 * !(A|B) into !A & !B
 * TODO: !(For all)x A into (Exists) x !A
 *       !(Exists)x A into (For all) x !A
 */
public ASTNode* negationsInward(ASTNode* node)
{
    if (node is null) return null;

    node.left  = negationsInward(node.left);
    node.right = negationsInward(node.right);

    if (node.type == NodeType.Negation) {
        if (node.left.type == NodeType.Negation) {
            return node.left.left;
        } else if (node.left.type == NodeType.Conjunction) {
            ASTNode* leftNegation  = new ASTNode(NodeType.Negation, ""d, node.left.left, null);
            ASTNode* rightNegation = new ASTNode(NodeType.Negation, ""d, node.left.right, null);
            node.type  = NodeType.Disjunction;
            node.left  = leftNegation;
            node.right = rightNegation;
            return negationsInward(node);
        } else if (node.left.type == NodeType.Disjunction) {
            ASTNode* leftNegation  = new ASTNode(NodeType.Negation, ""d, node.left.left, null);
            ASTNode* rightNegation = new ASTNode(NodeType.Negation, ""d, node.left.right, null);
            node.type  = NodeType.Conjunction;
            node.left  = leftNegation;
            node.right = rightNegation;
            return negationsInward(node);
        }
    }

    return node;
}

// Ax(P(x)) > Ex(P(x)) into Ax(P(x)) > Ey(P(y))
public ASTNode* standardizeVariables(ASTNode* node) 
{
    int x = 0;
    return standardizeVariables(node, x);
}

// Helper function
private ASTNode* standardizeVariables(ASTNode* node, ref int counter)
{
    if (node is null) return null;

    if (node.type == NodeType.Universal || node.type == NodeType.Existential) {
        dstring oldVar = node.value;
        // new var in the form of v0, v1, v2, etc.
        dstring newVar = format("v%d", counter++).toUTF32();
        node.value = newVar;

        replaceVariable(node.left, oldVar, newVar);
    }

    node.left  = standardizeVariables(node.left, counter);
    node.right = standardizeVariables(node.right, counter);

    return node;
}

// Helper function
private void replaceVariable(ASTNode* node, dstring oldVar, dstring newVar)
{
    if (node is null) return;

    if (node.type == NodeType.Variable && node.value == oldVar) {
        node.value = newVar;
    }

    replaceVariable(node.left, oldVar, newVar);
    replaceVariable(node.right, oldVar, newVar);

    foreach (arg; node.args) {
        replaceVariable(arg, oldVar, newVar);
    }
}

// Ax(P(x)) > Ey(P(y)) into AxEy(P(x) > P(y))
public ASTNode* moveQuantifiersToFront(ASTNode* node)
{
    auto quantifiers = extractQuantifiers(node);
    node = removeQuantifiers(node);
    foreach (q; quantifiers) {
        node = new ASTNode(q.type, q.value, node, null);
    }
    return node;
}

// helper function which returns a list of quantifiers
private ASTNode*[] extractQuantifiers(ASTNode* node)
{
    if (node is null) return [];
    ASTNode*[] quantifiers;
    if (node.type == NodeType.Universal || node.type == NodeType.Existential) {
        quantifiers ~= node;
    }

    auto left = extractQuantifiers(node.left);
    auto right = extractQuantifiers(node.right);

    return  right ~ left  ~ quantifiers;
}

// helper function which removes all quantifiers from the tree
private ASTNode* removeQuantifiers(ASTNode* node)
{
    if (node is null) return null;

    node.left  = removeQuantifiers(node.left);
    node.right = removeQuantifiers(node.right);

    if (node.type == NodeType.Universal || node.type == NodeType.Existential) {
        return node.left; // skip the quantifier
    } else {
        return node;
    }
}

public ASTNode* eliminateExistentialQuantifiers(ASTNode* node)
{
    ASTNode*[] uqList; // universal quantifier list
    ASTNode*[] fList; // skolem function list

    // formula should have all quantifiers at the front, so we can just collect them until we hit a non-quantifier
    int i = 0;
    while (node !is null && (node.type == NodeType.Universal || node.type == NodeType.Existential)) {
        if (node.type == NodeType.Universal) {
            uqList ~= node; // keep track of universal quantifiers for later
        } else {
            dstring skolemFuncName = format("f%d", i++).toUTF32();
            ASTNode* possibleSkolemFunc = new ASTNode(NodeType.SkolemFunction, skolemFuncName, null, null);
            ASTNode* args;
            if (uqList.length > 0) {
                foreach (uq; uqList) {
                    possibleSkolemFunc.args ~= new ASTNode(NodeType.Variable, uq.value, null, null);
                }
            } else {
                // generate fresh constant starting at a0, a1, a2, etc.
                dstring constantName = format("a%d", i++).toUTF32();
                possibleSkolemFunc = new ASTNode(NodeType.Variable, constantName, null, null);
            }

            replaceSkolemVariable(node.left, node, possibleSkolemFunc);
        }
        node = node.left;
    }

    node = removeQuantifiers(node);

    return node;
}

private void replaceSkolemVariable(ASTNode* node, ASTNode* existentialNode, ASTNode* skolemFunc)
{
    if (node is null) return;

    replaceSkolemVariable(node.left, existentialNode, skolemFunc);
    replaceSkolemVariable(node.right, existentialNode, skolemFunc);

    foreach (ref arg; node.args) {  // ref so we can replace
        if (arg.type == NodeType.Variable && arg.value == existentialNode.value) {
            arg = skolemFunc;       // replace the whole node, not just the value
        } else {
            replaceSkolemVariable(arg, existentialNode, skolemFunc);
        }
    }
}