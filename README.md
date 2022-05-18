# Canela-lang
Canela is an imperative programming language with functional features like algebraic types and lambdas. This repository contains the interpreter of this language.

## About
The interpreter was written in pure Haskell. Some code, especially the parser and the lexer, was generated automatically using [BNFC](https://bnfc.digitalgrammars.com/).

## How to use
Run `make` in the main directory. Then type `./interpreter program` where `program` is your input file.

## The language
You can check out the examples to see how to write in Canela. In the directory `good` you will find examples of correct programs. In the directory `bad` you will find examples of incorrect programs.
