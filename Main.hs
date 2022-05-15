module Main where

import Prelude
  ( ($), (.)
  , Either(..)
  , Int, (>)
  , String, (++), concat, unlines
  , Show, show
  , IO, (>>), (>>=), mapM_, putStrLn
  , FilePath
  , getContents, readFile
  )
import System.Environment ( getArgs )
import System.Exit        ( exitFailure )
import Control.Monad      ( when )

import AbsCanela   ( Program )
import LexCanela   ( Token, mkPosToken )
import ParCanela   ( pProgram, myLexer )
import PrintCanela ( Print, printTree )
import CanelaInterpreter  ( interpret )

type Err        = Either String
type ParseFun a = [Token] -> Err a
type Verbosity  = Int

putStrV :: Verbosity -> String -> IO ()
putStrV v s = when (v > 1) $ putStrLn s

runFile ::  Verbosity -> ParseFun Program -> FilePath -> IO ()
runFile v p f = readFile f >>= run v p

run :: Verbosity -> ParseFun Program -> String -> IO ()
run v p s =
  case p ts of
    Left err -> do
      putStrLn "\nParse              Failed...\n"
      putStrV v "Tokens:"
      mapM_ (putStrV v . showPosToken . mkPosToken) ts
      putStrLn err
      exitFailure
    Right program -> do
      interpret program
  where
  ts = myLexer s
  showPosToken ((l,c),t) = concat [ show l, ":", show c, "\t", show t ]

usage :: IO ()
usage = do
  putStrLn $ unlines
    [ "usage: "
    , "  --help          Display this help message."
    , "  (file)          Interpret the code in a given file."
    ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--help"] -> usage
    []         -> usage
    f:fs         -> runFile 2 pProgram f


{-
module Main where

import Prelude(IO, readFile)
import SkelCanela
import ParCanela(pProgram, myLexer)

interpret :: IO()
interpret file = do
    code <- readFile file;


main :: IO()
main = do
    args <- getArgs
    case args of 
        [] -> putStrLn "Program usage: ./Canela <input file directory>"
        arg:_ -> interpret arg
        -}
        