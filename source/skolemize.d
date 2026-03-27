module skolemize;

import std.stdio;

import model;
import parser;


public ASTNode* skolemizeNode(ASTNode* node)
{
    node = removeImplication(node);
    node = removeBiconditional(node);
    node = negationsInward(node);
    // TODO:
    // Standardize variables
    // Move quantifiers to the front
    // Eliminate existential quantifiers
    return node;
}

/// Turn A -> B into !A | B
public ASTNode* removeImplication(ASTNode* node)
{
    if (node is null) return null;

    node.left  = skolemizeNode(node.left);
    node.right = skolemizeNode(node.right);

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

    node.left  = skolemizeNode(node.left);
    node.right = skolemizeNode(node.right);

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
        } else if (node.left.type == NodeType.Disjunction) {
            ASTNode* leftNegation  = new ASTNode(NodeType.Negation, ""d, node.left.left, null);
            ASTNode* rightNegation = new ASTNode(NodeType.Negation, ""d, node.left.right, null);
            node.type  = NodeType.Conjunction;
            node.left  = leftNegation;
            node.right = rightNegation;
        }
    }

    return node;
}