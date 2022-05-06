-- File generated by the BNF Converter (bnfc 2.9.4).

-- Templates for pattern matching on abstract syntax

{-# OPTIONS_GHC -fno-warn-unused-matches #-}

module SkelCanela where

import Prelude
import System.IO ( hPutStrLn, stderr )
import qualified AbsCanela

import Control.Monad.Identity
import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Writer
import Data.Maybe

import qualified Data.Map as Map 

-- TODO: Lambdas shall be done at the end.
data Value 
    = Void
    | Int Integer 
    | Str String 
    | Bool Bool 
    | UserType [Value] 
    | Fun AbsCanela.Type [(AbsCanela.Ident, AbsCanela.Type)] AbsCanela.Block Env 
    | Enum EnumMap
    | NoReturnFlag
  deriving (Eq, Ord, Show, Read)
type Loc = Integer
type Mem = Map.Map Loc Value

type Var = (AbsCanela.AccessType, Loc)
type Env = Map.Map AbsCanela.Ident Var
type EnumMap = Map.Map AbsCanela.Ident [AbsCanela.Type]

type Run a = ReaderT Env (ExceptT String (StateT Mem IO)) a
type Result a = Run a

locBankLoc :: Loc
locBankLoc = 0

returnLoc :: Loc
returnLoc = 1

minimalLoc :: Loc
minimalLoc = 2

newloc :: Result Loc
newloc = do
  st <- get
  case Map.lookup locBankLoc st of
    Just (Int x) -> do
      put (Map.insert locBankLoc (Int (x + 1)) st)
      return x
    _ -> do 
      throwError $ "CRITICAL ERROR: Newloc did not obtain an int.";
      return 0;
  

failure :: Show a => a -> Result ()
failure x = do throwError $ "CRITICAL ERROR: Undefined case: " ++ show x;
               return ();
{-
transIdent :: AbsCanela.Ident -> Result
transIdent x = case x of
  AbsCanela.Ident string -> failure x
-}

printStderr :: String -> Result ()
printStderr err = liftIO $ hPutStrLn stderr err

showPos :: AbsCanela.BNFC'Position -> String
showPos (Just (x, y)) = "row " ++ (show x) ++ ", col " ++ (show y)
showPos Nothing = "unknown position"

raiseError :: String -> AbsCanela.BNFC'Position -> Result ()
raiseError str pos = do 
  throwError $ "ERROR AT " ++ (showPos pos) ++ ": " ++ str

interpret :: AbsCanela.Program -> IO ()
interpret program = do
  let initialState = Map.fromList [(locBankLoc, (Int minimalLoc)), (returnLoc, NoReturnFlag)]
  x <- runStateT (runExceptT (runReaderT monad Map.empty)) (initialState);
  case x of
    ((Left err), _) -> hPutStrLn stderr err
    _ -> return ()
    where
      monad = runProgram program

runProgram :: AbsCanela.Program -> Result ()
runProgram (AbsCanela.Program pos topdefs) = do
  env <- readTopDefs topdefs
  mainRes <- local (\_ -> env) (eval $ AbsCanela.EApp pos (AbsCanela.Ident "main") [])
  case mainRes of
    (Int x) -> printStderr $ "Main returned " ++ (show x) ++ "."
    _ -> printStderr $ "Function main does not return Int."
  return ()

readTopDefs :: [AbsCanela.TopDef] -> Result Env
readTopDefs defs = case defs of
  [] -> do
    env <- ask;
    return env
  d:ds -> do
    newEnv <- declTopDef d;
    local (\_ -> newEnv) $ do 
      finalEnv <- readTopDefs ds
      return finalEnv

addArgToEnv :: Env -> AbsCanela.Arg -> Env
addArgToEnv env (AbsCanela.Arg _ accessType _ ident) = Map.insert ident (accessType, 0) env

-- TODO: Check typing
declTopDef :: AbsCanela.TopDef -> Result Env
declTopDef x = case x of
  AbsCanela.FnDef pos type_ ident args block -> do
    env <- ask
    loc <- newloc
    st <- get

    -- newEnv adds the function into the environment,
    -- finalEnv also contains the function's arguments as local variables.
    -- Hence, other functions should only see this function, 
    -- but this function can also see its variables.
    let newEnv = Map.insert ident ((AbsCanela.Const pos), loc) env
    let finalEnv = Map.union newEnv $ foldl addArgToEnv Map.empty args
    let vars = map (\(AbsCanela.Arg _ _ t i) -> (i, t)) args

    let fun = (Fun type_ vars block finalEnv)
    put $ Map.insert loc fun st
    return newEnv
  AbsCanela.EnDef pos ident envardefs -> do
    env <- ask
    loc <- newloc
    st <- get

    let newEnv = Map.insert ident ((AbsCanela.Const pos), loc) env

    let mapping = \m (AbsCanela.EnVarDef _ ident types) -> Map.insert ident types m
    let enum = Enum (foldl mapping Map.empty envardefs)
    put $ Map.insert loc enum st

    return Map.empty

transArg :: AbsCanela.Arg -> Result ()
transArg x = case x of
  AbsCanela.Arg _ accesstype type_ ident -> failure x

transEnVarDef :: Show a => AbsCanela.EnVarDef' a -> Result ()
transEnVarDef x = case x of
  AbsCanela.EnVarDef _ ident types -> failure x

transBlock :: Show a => AbsCanela.Block' a -> Result ()
transBlock x = case x of
  AbsCanela.Block _ stmts -> failure x

exec :: AbsCanela.Stmt -> Result ()
exec x = do
  st <- get
  case Map.lookup returnLoc st of
    Just NoReturnFlag -> transStmt x;
    Nothing -> do throwError "CRITICAL ERROR: Return loc is empty"; return ();
    _ -> return ();

execStmtList :: [AbsCanela.Stmt] -> Result ()
execStmtList [] = return ()
execStmtList (stmt:stmts) = do
  exec stmt >> execStmtList stmts

transStmt :: AbsCanela.Stmt -> Result ()
transStmt x = case x of
  AbsCanela.Empty _ -> return ();
  AbsCanela.BStmt _ (AbsCanela.Block _ stmts) -> do
    execStmtList stmts
  AbsCanela.Decl _ accesstype type_ items -> failure x
  AbsCanela.Ass _ ident expr -> failure x
  AbsCanela.Incr _ ident -> failure x
  AbsCanela.Decr _ ident -> failure x
  AbsCanela.Ret _ expr -> do
    st <- get
    value <- eval expr
    put $ Map.insert returnLoc value st
  AbsCanela.VRet _ -> do
    st <- get
    put $ Map.insert returnLoc Void st
  AbsCanela.Cond _ expr block -> failure x
  AbsCanela.CondElse _ expr block1 block2 -> failure x
  AbsCanela.Match _ expr matchbranchs -> failure x
  AbsCanela.While _ expr stmt -> failure x
  AbsCanela.For _ ident expr1 expr2 block -> failure x
  AbsCanela.SExp _ expr -> failure x

transItem :: Show a => AbsCanela.Item' a -> Result ()
transItem x = case x of
  AbsCanela.NoInit _ ident -> failure x
  AbsCanela.Init _ ident expr -> failure x

transMatchBranch :: Show a => AbsCanela.MatchBranch' a -> Result ()
transMatchBranch x = case x of
  AbsCanela.MatchBr _ matchvar block -> failure x

transMatchVar :: Show a => AbsCanela.MatchVar' a -> Result ()
transMatchVar x = case x of
  AbsCanela.MatchVar _ ident1 ident2 idents -> failure x
  AbsCanela.MatchDefault _ -> failure x

transType :: Show a => AbsCanela.Type' a -> Result ()
transType x = case x of
  AbsCanela.Int _ -> failure x
  AbsCanela.Str _ -> failure x
  AbsCanela.Bool _ -> failure x
  AbsCanela.Void _ -> failure x
  AbsCanela.Func _ -> failure x
  AbsCanela.UserType _ ident -> failure x
  AbsCanela.Fun _ type_ types -> failure x

transAccessType :: Show a => AbsCanela.AccessType' a -> Result ()
transAccessType x = case x of
  AbsCanela.Const _ -> failure x
  AbsCanela.Mutable _ -> failure x

getFunction :: AbsCanela.Ident -> AbsCanela.BNFC'Position -> Result Value
getFunction ident pos = do
  env <- ask
  st <- get
  case Map.lookup ident env of
    Just (_, loc) -> case Map.lookup loc st of
      Just (Fun t as b e) -> return (Fun t as b e)
      _ -> do 
        raiseError ("Object " ++ (show ident) ++ " is not a function.") pos
        return Void
    _ -> do 
      raiseError ((show ident) ++ " was not declared.") pos
      return Void

eval :: AbsCanela.Expr -> Result Value
eval x = case x of
  AbsCanela.ELitInt _ integer -> return (Int integer)
  AbsCanela.EApp pos ident exprs -> do 
    -- TODO: Add passing arguments (and checking their type correctness).
    (Fun _ _ block env) <- getFunction ident pos
    
    local (\_ -> env) $ do 
      -- TODO: Add returns.
      exec (AbsCanela.BStmt pos block)
      st <- get
      case Map.lookup returnLoc st of
        Just NoReturnFlag -> do 
          return Void;
        Just x -> do 
          put $ Map.insert returnLoc NoReturnFlag st;
          return x;
        Nothing -> do 
          throwError "CRITICAL ERROR: Return loc is empty"; 
          return Void;

  _ -> do 
    failure x
    return (Int 1)
{-
eval x = case x of
  AbsCanela.ELambda _ args block -> failure x
  AbsCanela.EEnum _ ident1 ident2 exprs -> failure x
  AbsCanela.EVar _ ident -> failure x
  AbsCanela.ELitInt _ integer -> failure x
  AbsCanela.ELitTrue _ -> failure x
  AbsCanela.ELitFalse _ -> failure x
  AbsCanela.EApp _ ident exprs -> failure x
  AbsCanela.EString _ string -> failure x
  AbsCanela.Neg _ expr -> failure x
  AbsCanela.Not _ expr -> failure x
  AbsCanela.EMul _ expr1 mulop expr2 -> failure x
  AbsCanela.EAdd _ expr1 addop expr2 -> failure x
  AbsCanela.ERel _ expr1 relop expr2 -> failure x
  AbsCanela.EAnd _ expr1 expr2 -> failure x
  AbsCanela.EOr _ expr1 expr2 -> failure x
-}

transAddOp :: Show a => AbsCanela.AddOp' a -> Result ()
transAddOp x = case x of
  AbsCanela.Plus _ -> failure x
  AbsCanela.Minus _ -> failure x

transMulOp :: Show a => AbsCanela.MulOp' a -> Result ()
transMulOp x = case x of
  AbsCanela.Times _ -> failure x
  AbsCanela.Div _ -> failure x
  AbsCanela.Mod _ -> failure x

transRelOp :: Show a => AbsCanela.RelOp' a -> Result ()
transRelOp x = case x of
  AbsCanela.LTH _ -> failure x
  AbsCanela.LE _ -> failure x
  AbsCanela.GTH _ -> failure x
  AbsCanela.GE _ -> failure x
  AbsCanela.EQU _ -> failure x
  AbsCanela.NE _ -> failure x
