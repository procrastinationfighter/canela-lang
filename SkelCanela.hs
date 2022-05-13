-- File generated by the BNF Converter (bnfc 2.9.4).

-- Templates for pattern matching on abstract syntax

{-# OPTIONS_GHC -fno-warn-unused-matches #-}

module SkelCanela where

import Prelude
import System.IO ( hPutStrLn, stderr )
import System.Exit
import qualified AbsCanela

import Control.Monad.Identity
import Control.Monad.Except
import Control.Monad.Reader
import Control.Monad.State
import Control.Monad.Writer
import Data.Maybe

import qualified Data.Map as Map 

data Value 
    = Void
    | Int Integer 
    | Str String 
    | Bool Bool 
    | UserType AbsCanela.Ident AbsCanela.Ident [Value] 
    | Fun AbsCanela.Type [(AbsCanela.Ident, AbsCanela.Type)] AbsCanela.Block Env 
    | Enum EnumMap
    | NoReturnFlag
    | ReturnVal Value AbsCanela.BNFC'Position
    | ErrorVal
  deriving (Eq, Ord, Show, Read)
type Loc = Integer
type Mem = Map.Map Loc Value

type Var = (AbsCanela.AccessType, Loc)
type Env = Map.Map AbsCanela.Ident Var
type EnumMap = Map.Map AbsCanela.Ident [AbsCanela.Type]

type Run a = ReaderT Env (ExceptT String (StateT Mem IO)) a
type Result a = Run a

noLoc :: Loc
noLoc = -1

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
    (Int 0) -> liftIO $ exitWith ExitSuccess
    (Int x) -> liftIO $ exitWith (ExitFailure $ fromIntegral x)
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
addArgToEnv env (AbsCanela.Arg _ accessType _ ident) = 
  Map.insert ident (accessType, noLoc) env

createFun :: AbsCanela.Type -> [AbsCanela.Arg] -> Env -> AbsCanela.Block -> Result Value
createFun type_ args env block = do
  let finalEnv = Map.union env $ foldl addArgToEnv Map.empty args
  let vars = map (\(AbsCanela.Arg _ _ t i) -> (i, t)) args
  return (Fun type_ vars block finalEnv)

-- TODO: Check typing at declaration moment
declTopDef :: AbsCanela.TopDef -> Result Env
declTopDef x = case x of
  AbsCanela.FnDef pos type_ ident args block -> do
    env <- ask
    loc <- newloc
    st <- get

    -- newEnv adds the function into the environment,
    -- createFun creates a function with its variables in the enviroment.
    -- Hence, other functions should only see this function, 
    -- but this function can also see its variables.
    let newEnv = Map.insert ident ((AbsCanela.Const pos), loc) env
    fun <- createFun type_ args newEnv block
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

    return newEnv

transArg :: AbsCanela.Arg -> Result ()
transArg x = case x of
  AbsCanela.Arg _ accesstype type_ ident -> failure x

transEnVarDef :: Show a => AbsCanela.EnVarDef' a -> Result ()
transEnVarDef x = case x of
  AbsCanela.EnVarDef _ ident types -> failure x

transBlock :: Show a => AbsCanela.Block' a -> Result ()
transBlock x = case x of
  AbsCanela.Block _ stmts -> failure x

exec :: AbsCanela.Stmt -> Result Env
exec x = do
  env <- ask
  st <- get
  case Map.lookup returnLoc st of
    Just NoReturnFlag -> transStmt x;
    Nothing -> do throwError "CRITICAL ERROR: Return loc is empty"; return Map.empty;
    _ -> return env;

execStmtList :: [AbsCanela.Stmt] -> Result Env
execStmtList [] = ask
execStmtList (stmt:stmts) = do
  env <- exec stmt
  local (\_ -> env) $ execStmtList stmts

checkIfEnumExists :: AbsCanela.Ident -> AbsCanela.BNFC'Position -> Result ()
checkIfEnumExists ident pos = do
  env <- ask
  st <- get
  case Map.lookup ident env of
    Just (_, loc) -> case Map.lookup loc st of
      Just (Enum _) -> return ()
      _ -> do raiseError ((show ident) ++ " is not a type.") pos; return ();
    Nothing -> do raiseError ("Type " ++ (show ident) ++ " was not defined.") pos; return ();

getItemIdent :: AbsCanela.Item -> AbsCanela.Ident
getItemIdent (AbsCanela.Init _ ident _) = ident
getItemIdent (AbsCanela.NoInit _ ident) = ident

getItemPos :: AbsCanela.Item -> AbsCanela.BNFC'Position
getItemPos (AbsCanela.Init pos _ _) = pos
getItemPos (AbsCanela.NoInit pos _) = pos

{-
data Value 
    = Void
    | Int Integer 
    | Str String 
    | Bool Bool 
    | UserType [Value] 
    | Fun AbsCanela.Type [(AbsCanela.Ident, AbsCanela.Type)] AbsCanela.Block Env 
    | Enum EnumMap
    | NoReturnFlag
    | ErrorVal
  deriving (Eq, Ord, Show, Read)
-}

handleValuesTypesMatch :: Bool -> AbsCanela.BNFC'Position -> Result ()
handleValuesTypesMatch cond pos = do
  if cond 
    then return ()
    else do raiseError "Left hand side and right hand side types do not match!" pos; return ();

checkIfValuesTypesMatch :: Value -> Value -> AbsCanela.BNFC'Position -> Result ()
checkIfValuesTypesMatch (UserType enumIdent1 _ _) (UserType enumIdent2 _ _) pos = handleValuesTypesMatch (enumIdent1 == enumIdent2) pos
checkIfValuesTypesMatch l r pos = do
  let lType = f l 
  let rType = f r
  handleValuesTypesMatch (lType == rType) pos
    where
      f Void = 0
      f (Int _) = 1
      f (Str _) = 2
      f (Bool _) = 3
      f (UserType _ _ _) = 4
      f (Fun _ _ _ _) = 5

checkValueType :: Value -> AbsCanela.Type -> AbsCanela.BNFC'Position -> Result ()
checkValueType (Void) (AbsCanela.Void _) _ = return ()
checkValueType (Int _) (AbsCanela.Int _) _ = return ()
checkValueType (Str _) (AbsCanela.Str _) _ = return ()
checkValueType (Bool _) (AbsCanela.Bool _) _ = return ()
checkValueType (Fun _ _ _ _) (AbsCanela.Func _) _ = return ()
-- TODO: Checking functional type could be simplified if Fun in memory kept the AbsCanela.Fun type.
checkValueType (Fun retType1 leftArgs _ _) (AbsCanela.Fun _ retType2 args2) pos = do
  let retOk = AbsCanela.compareAbsType retType1 retType2
  let args1 = map (\x -> snd x) leftArgs
  let argsOk = AbsCanela.compareArgsType args1 args2
  if retOk
    then if argsOk
      then
        return ()
      else do
        raiseError ("Functional types' arguments do not match.") pos; return ();
    else do
        raiseError ("Functional types' return types do not match.") pos; return ();
checkValueType (UserType enumIdent1 _ _) (AbsCanela.UserType typePos enumIdent2) pos = do
  if enumIdent1 == enumIdent2
    then return ()
  else checkValueType (Int 1) (AbsCanela.UserType typePos enumIdent2) pos
checkValueType _ type_ pos = do raiseError ("Expression is not of type " ++ (show type_)) pos; return ();

getDefaultVarValue :: AbsCanela.Type -> Result Value
getDefaultVarValue (AbsCanela.Int _) = return (Int 0)
getDefaultVarValue (AbsCanela.Str _) = return (Str "")
getDefaultVarValue (AbsCanela.Bool _) = return (Bool False)
getDefaultVarValue (AbsCanela.Func pos) = return (Fun (AbsCanela.Void pos) [] (AbsCanela.Block pos []) Map.empty)
getDefaultVarValue (AbsCanela.UserType pos _) = do
  raiseError "Enum variants can't have a default value." pos
  return ErrorVal
getDefaultVarValue _ = do
  throwError "CRITICAL ERROR: DEFAULT VALUE FOR THIS TYPE DOES NOT EXIST"
  return (Int 0)

initVariable :: AbsCanela.Item -> AbsCanela.AccessType -> AbsCanela.Type -> Result Env
initVariable item accessType type_ = do 
  env <- ask
  loc <- newloc
  
  let ident = getItemIdent item
  let newEnv = Map.insert ident (accessType, loc) env
  val <- case item of
    (AbsCanela.Init pos _ expr) -> do
      value <- eval expr
      checkValueType value type_ pos
      return value
    (AbsCanela.NoInit pos _) -> getDefaultVarValue type_
  
  st <- get
  put $ Map.insert loc val st
  return newEnv

declVars :: [AbsCanela.Item] -> AbsCanela.AccessType -> AbsCanela.Type -> Result Env
declVars [] _ _ = ask
declVars (item:items) accessType type_ = do
  env <- ask
  let ident = getItemIdent item
  let pos = AbsCanela.hasPosition item
  env <- initVariable item accessType type_
  local (\_ -> env) $ do
    declVars items accessType type_

execFor :: AbsCanela.Stmt -> Loc -> Integer -> Result Env 
execFor stmt loc limit = do
  st <- get
  case Map.lookup loc st of
    (Just (Int x)) -> do
      if x < limit 
        then do
          exec stmt
          st <- get
          put $ Map.insert loc (Int (x + 1)) st

          -- If Return occured inside the loop, don't do more iterations.
          case Map.lookup returnLoc st of
            Just NoReturnFlag -> execFor stmt loc limit
            _ -> ask
        else
          ask
    _ -> do throwError "CRITICAL ERROR: Iterator not found in the state."; ask;

assignBranchVars :: [Value] -> [AbsCanela.Ident] -> AbsCanela.BNFC'Position -> Result Env
assignBranchVars [] [] _ = ask
assignBranchVars vals [] pos = do
  raiseError "Match unsuccesful: not enough variables" pos
  return Map.empty
assignBranchVars [] vars pos = do
  raiseError "Match unsuccesful: too many variables" pos
  return Map.empty
assignBranchVars (val:vals) (var:vars) pos = do
  env <- assignBranchVars vals vars pos
  loc <- newloc
  st <- get
  let newEnv = Map.insert var ((AbsCanela.Const pos), loc) env
  put $ Map.insert loc val st
  return newEnv

getMatchBranchEnv :: Value -> AbsCanela.MatchVar -> AbsCanela.BNFC'Position -> Result Env
getMatchBranchEnv _ (AbsCanela.MatchDefault _) _ = ask
getMatchBranchEnv (UserType _ _ vals) (AbsCanela.MatchVar _ _ _ vars) pos = assignBranchVars vals vars pos

checkMatch :: Value -> AbsCanela.MatchVar -> AbsCanela.BNFC'Position -> Result Bool
-- TODO: Add matches for other types than enums.
checkMatch _ (AbsCanela.MatchDefault _) _ = return True
checkMatch (UserType enumIdent1 variantIdent1 _) (AbsCanela.MatchVar _ enumIdent2 variantIdent2 _) pos = 
  return $ enumIdent1 == enumIdent2 && variantIdent1 == variantIdent2

findMatch :: Value -> [AbsCanela.MatchBranch] -> AbsCanela.BNFC'Position -> Result ()
findMatch _ [] pos = do
  raiseError "No match found." pos;
  return ()
findMatch val ((AbsCanela.MatchBr brPos variant block):bs) pos = do
  ok <- checkMatch val variant pos
  if ok 
    then do
      env <- getMatchBranchEnv val variant pos
      local (\_ -> env) $ exec (AbsCanela.BStmt brPos block)
      return ()
    else
      findMatch val bs pos

transStmt :: AbsCanela.Stmt -> Result Env
transStmt x = case x of
  AbsCanela.Empty _ -> ask
  AbsCanela.BStmt _ (AbsCanela.Block _ stmts) -> do 
    execStmtList stmts
    ask
  AbsCanela.Decl _ accessType type_ items -> do
    -- Check if type is correct 
    case type_ of
      (AbsCanela.Void pos) -> do raiseError "Variables can't be of type Void." pos; return Map.empty;
      (AbsCanela.UserType pos ident) -> do 
        checkIfEnumExists ident pos
        declVars items accessType type_
      _ -> declVars items accessType type_
  AbsCanela.TopDecl _ topdef -> declTopDef topdef
  AbsCanela.Ass pos ident expr -> do 
    env <- ask
    st <- get
    case Map.lookup ident env of
      Just (AbsCanela.Const _, _) -> do raiseError ("Variable " ++ (show ident) ++ " is immutable.") pos; ask;
      Just (AbsCanela.Mutable _, loc) -> do
        case Map.lookup loc st of
          Just x -> do
            value <- eval expr
            checkIfValuesTypesMatch x value pos
            newSt <- get
            put $ Map.insert loc value newSt
            ask
          Nothing -> do throwError $ "CRITICAL ERROR: State for loc " ++ (show loc) ++ " is empty"; ask;
      Nothing -> do raiseError ("Object " ++ (show ident) ++ " was not defined.") pos; ask;
  AbsCanela.Incr pos ident -> do 
    value <- eval (AbsCanela.EVar pos ident)
    case value of
      (Int x) -> exec (AbsCanela.Ass pos ident (AbsCanela.ELitInt pos (x + 1)))
      _ -> do raiseError ("Variable " ++ (show ident) ++ " is not of type int.") pos; ask;
  AbsCanela.Decr pos ident -> do 
    value <- eval (AbsCanela.EVar pos ident)
    case value of
      (Int x) -> exec (AbsCanela.Ass pos ident (AbsCanela.ELitInt pos (x - 1)))
      _ -> do raiseError ("Variable " ++ (show ident) ++ " is not of type int.") pos; ask;
  AbsCanela.Ret pos expr -> do
    value <- eval expr
    st <- get
    put $ Map.insert returnLoc (ReturnVal value pos) st
    ask
  AbsCanela.VRet pos -> do
    st <- get
    put $ Map.insert returnLoc (ReturnVal Void pos) st
    ask
  AbsCanela.Cond pos expr block -> do 
    (Bool b) <- evalBool expr pos
    if b
      then exec (AbsCanela.BStmt pos block)
      else ask
  AbsCanela.CondElse pos expr block1 block2 -> do 
    (Bool b) <- evalBool expr pos
    if b
      then exec (AbsCanela.BStmt pos block1)
      else exec (AbsCanela.BStmt pos block2)
  AbsCanela.Match pos expr branches -> do 
    val <- eval expr
    findMatch val branches pos
    ask
  AbsCanela.While pos expr stmt -> do 
    (Bool b) <- evalBool expr pos
    if b
      then do
        exec stmt
        exec (AbsCanela.While pos expr stmt)
      else ask
  AbsCanela.For pos ident expr1 expr2 block -> do 
    (Int left) <- evalInt expr1 pos
    (Int right) <- evalInt expr2 pos 
    -- Declare the new variable.
    let initVal = (AbsCanela.ELitInt pos left)
    let initItems = [(AbsCanela.Init pos ident initVal)]
    newEnv <- exec (AbsCanela.Decl pos (AbsCanela.Const pos) (AbsCanela.Int pos) initItems)

    case Map.lookup ident newEnv of
      Just (_, loc) -> local (\_ -> newEnv) $ execFor (AbsCanela.BStmt pos block) loc right
      _ -> do throwError "CRITICAL ERROR: Iterator not found in the environment"; ask;
  AbsCanela.SExp _ expr -> do
    _ <- eval expr
    ask

transMatchVar :: Show a => AbsCanela.MatchVar' a -> Result ()
transMatchVar x = case x of
  AbsCanela.MatchVar _ ident1 ident2 idents -> failure x
  AbsCanela.MatchDefault _ -> failure x

getFunction :: AbsCanela.Ident -> AbsCanela.BNFC'Position -> Result Value
getFunction ident pos = do
  env <- ask
  st <- get
  case Map.lookup ident env of
    Just (_, loc) -> case Map.lookup loc st of
      Just (Fun t as b e) -> return (Fun t as b e)
      _ -> do 
        raiseError ("Object " ++ (show ident) ++ " is not a function.") pos
        return ErrorVal
    _ -> do 
      raiseError ("Function " ++ (show ident) ++ " was not declared.") pos
      return ErrorVal

compareValues :: AbsCanela.RelOp -> Value -> Value -> AbsCanela.BNFC'Position -> Result Bool
compareValues (AbsCanela.NE p) v1 v2 pos = do
  res <- compareValues (AbsCanela.EQU p) v1 v2 pos
  return $ not res
compareValues (AbsCanela.GE p) v1 v2 pos = do
  eq <- compareValues (AbsCanela.EQU p) v1 v2 pos 
  gth <- compareValues (AbsCanela.GTH p) v1 v2 pos
  return $ eq || gth
compareValues (AbsCanela.LE p) v1 v2 pos = do
  res <- compareValues (AbsCanela.GTH p) v1 v2 pos
  return $ not res
compareValues (AbsCanela.LTH p) v1 v2 pos = do 
  res <- compareValues (AbsCanela.GE p) v1 v2 pos
  return $ not res
compareValues (AbsCanela.EQU _) (Bool b1) (Bool b2) _ = return $ b1 == b2
compareValues (AbsCanela.EQU _) (Int i1) (Int i2) _ = return $ i1 == i2
compareValues (AbsCanela.EQU _) (Str s1) (Str s2) _ = return $ s1 == s2
compareValues (AbsCanela.GTH _) (Bool b1) (Bool b2) _ = return $ b1 > b2
compareValues (AbsCanela.GTH _) (Int i1) (Int i2) _ = return $ i1 > i2
compareValues (AbsCanela.GTH _) (Str s1) (Str s2) _ = return $ s1 > s2
compareValues _ (UserType _ _ _) (UserType _ _ _) pos = do
  raiseError "Enum variants are not comparable. " pos
  return False
compareValues _ _ _ pos = do 
  raiseError "The types are not comparable." pos; 
  return False;

evalBool :: AbsCanela.Expr -> AbsCanela.BNFC'Position -> Result Value
evalBool expr pos = do
  cond <- eval expr
  checkValueType cond (AbsCanela.Bool pos) pos
  return cond

evalInt :: AbsCanela.Expr -> AbsCanela.BNFC'Position -> Result Value
evalInt expr pos = do
  cond <- eval expr
  checkValueType cond (AbsCanela.Int pos) pos
  return cond

getArgumentLoc :: AbsCanela.Expr -> AbsCanela.AccessType -> Result Loc
getArgumentLoc (AbsCanela.EVar pos ident) argAccessType = do
  env <- ask
  case Map.lookup ident env of
    Just (accessType, loc) -> do
      checkAccessType accessType argAccessType
      return loc;
    Nothing -> do
      raiseError ("Variable " ++ (show ident) ++ " was not declared.") pos
      return noLoc;
    where
      checkAccessType (AbsCanela.Const _) (AbsCanela.Mutable _) = do 
        raiseError ("Variable " ++ (show ident) ++ " is immutable and can't be passed as mutable.") pos
        return ()
      checkAccessType _ _ = return ()

getArgumentLoc _ _ = return noLoc

genericPrint :: String -> Result ()
genericPrint s = do
  liftIO $ putStr s
  return ()

printValueList :: [Value] -> AbsCanela.BNFC'Position -> Result ()
printValueList [] _ = return ()
printValueList ((UserType id1 id2 values):vs) pos = do
  genericPrint "("
  printValue (UserType id1 id2 values) pos
  genericPrint ")"
  printValueList vs pos
printValueList (v:vs) pos = do
  printValue v pos
  genericPrint " "
  printValueList vs pos

printValue :: Value -> AbsCanela.BNFC'Position -> Result ()
printValue (Void) _ = genericPrint "Void"
printValue (Int x) _ = genericPrint (show x)
printValue (Str s) _ = genericPrint s
printValue (Bool True) _ = genericPrint "true"
printValue (Bool False) _ = genericPrint "false"
printValue (Fun _ _ _ _) _ = genericPrint "Func"
printValue (UserType (AbsCanela.Ident enumName) (AbsCanela.Ident variantName) values) pos = do
  genericPrint $ (showString enumName . showString "::" . showString variantName) " "
  printValueList values pos
printValue _ pos = do
  raiseError "This value type can't be printed." pos
  return ()

printExprs :: [AbsCanela.Expr] -> Result ()
printExprs [] = return ()
printExprs (e:es) = do
  val <- eval e 
  printValue val (AbsCanela.hasPosition e)
  if es /= [] 
    then do genericPrint " "; printExprs es;
    else printExprs es;

passArguments :: Env -> [(AbsCanela.Ident, AbsCanela.Type)] -> [AbsCanela.Expr] -> AbsCanela.BNFC'Position -> Result Env
passArguments env [] [] _ = return env
passArguments _ [] exprs pos = do
  raiseError "Too many arguments." pos
  return Map.empty
passArguments _ args [] pos = do
  raiseError "Not enough arguments." pos
  return Map.empty
passArguments env ((ident, type_):as) (e:es) pos = do
  val <- eval e
  checkValueType val type_ (AbsCanela.hasPosition e)
  case Map.lookup ident env of
    Just (accessType, _) -> do
      newLoc <- getArgumentLoc e accessType

      if newLoc == noLoc
        then do
          finalLoc <- newloc
          st <- get
          let newEnv = Map.insert ident (accessType, finalLoc) env
          put $ Map.insert finalLoc val st
          passArguments newEnv as es pos
        else do
          let newEnv = Map.insert ident (accessType, newLoc) env
          passArguments newEnv as es pos
    Nothing -> do throwError "CRITICAL ERROR: Argument was not initialized."; return Map.empty;

getEnumVariant :: AbsCanela.Ident -> AbsCanela.Ident -> AbsCanela.BNFC'Position -> Result [AbsCanela.Type]
getEnumVariant enumIdent variantIdent pos = do
  env <- ask
  st <- get

  case Map.lookup enumIdent env of
    Just (_, loc) -> do
      case Map.lookup loc st of
        Just (Enum enumMap) -> do
          case Map.lookup variantIdent enumMap of
            Just types -> return types
            Nothing -> do
              raiseError "Enum variant was not declared." pos
              return []
        _ -> do
          throwError "CRITICAL ERROR: Enum not found in memory."
          return []
    Nothing -> do
      raiseError "Enum type was not declared." pos;
      return []

getEnumVariantValues :: [AbsCanela.Expr] -> [AbsCanela.Type] -> AbsCanela.BNFC'Position -> Result [Value]
getEnumVariantValues [] [] _ = return []
getEnumVariantValues exprs [] pos = do
  raiseError "Enum variant constructor has too many arguments." pos
  return []
getEnumVariantValues [] types pos = do
  raiseError "Enum variant constructor doesn't have enough arguments." pos
  return []
getEnumVariantValues (e:es) (t:ts) pos = do
  val <- eval e
  checkValueType val t pos
  valuesTail <- getEnumVariantValues es ts pos
  return (val:valuesTail) 

eval :: AbsCanela.Expr -> Result Value
eval x = case x of
  AbsCanela.ELambda _ args type_ block -> do 
    env <- ask
    createFun type_ args env block
  AbsCanela.EEnum pos enumIdent variantIdent exprs -> do
    enumVariant <- getEnumVariant enumIdent variantIdent pos
    enumValues <- getEnumVariantValues exprs enumVariant pos
    return (UserType enumIdent variantIdent enumValues)
  AbsCanela.EVar pos ident -> do
    env <- ask
    st <- get

    case Map.lookup ident env of
      Just (_, loc) -> case Map.lookup loc st of
        Just x -> return x;
        Nothing -> do 
          liftIO $ putStrLn $ show env
          liftIO $ putStrLn $ show (Map.keys st)
          throwError ("CRITICAL ERROR: location of variable " ++ (show ident) ++ " does not exist."); 
          return ErrorVal;
      Nothing -> do 
        raiseError ("Variable " ++ (show ident) ++ " was not declared") pos 
        return ErrorVal
  AbsCanela.ELitInt _ integer -> return (Int integer)
  AbsCanela.ELitTrue _ -> return (Bool True)
  AbsCanela.ELitFalse _ -> return (Bool False)
  AbsCanela.EString _ string -> return (Str string)
  AbsCanela.EApp pos (AbsCanela.Ident "print") exprs -> do
    -- Although print acts like a function,
    -- it's a bit more powerful, 
    -- since it can have many different arguments.
    printExprs exprs
    return Void
  AbsCanela.EApp pos ident exprs -> do 
    origEnv <- ask
    (Fun retType args block env) <- getFunction ident pos
    newEnv <- passArguments env args exprs pos
    
    local (\_ -> newEnv) $ do 
      exec (AbsCanela.BStmt pos block)
      st <- get
      case Map.lookup returnLoc st of
        Just NoReturnFlag -> do 
          case retType of 
            AbsCanela.Void _ -> return Void
            _ -> do
              raiseError ("Function " ++ show ident ++ " did not return anything.") pos
              return Void
        Just (ReturnVal x retPos) -> do 
          newSt <- get
          put $ Map.insert returnLoc NoReturnFlag newSt;
          checkValueType x retType retPos 
          return x;
        Nothing -> do 
          throwError "CRITICAL ERROR: Return loc does not contain a right value."; 
          return ErrorVal;
  AbsCanela.Neg pos expr -> do
    (Int i) <- evalInt expr pos
    return (Int $ negate i)
  AbsCanela.Not pos expr -> do
    (Bool b) <- evalBool expr pos
    return (Bool $ not b)
  AbsCanela.EMul pos expr1 mulop expr2 -> do
    (Int i1) <- evalInt expr1 pos
    (Int i2) <- evalInt expr2 pos
    case mulop of
      (AbsCanela.Times _) -> return (Int $ i1 * i2)
      (AbsCanela.Div pos) -> if i2 == 0 
        then do
          raiseError "Division by 0" pos
          return (Int 0)
        else return (Int $ i1 `div` i2)
      (AbsCanela.Mod pos) -> if i2 == 0 
        then do
          raiseError "Modulo division by 0" pos
          return (Int 0)
        else return (Int $ i1 `mod` i2)
  AbsCanela.EAdd pos expr1 addop expr2 -> do
    (Int i1) <- evalInt expr1 pos
    (Int i2) <- evalInt expr2 pos
    case addop of
      (AbsCanela.Plus _) -> return (Int $ i1 + i2)
      (AbsCanela.Minus _) -> return (Int $ i1 - i2)
  AbsCanela.ERel pos expr1 relop expr2 -> do
    val1 <- eval expr1
    val2 <- eval expr2
    result <- compareValues relop val1 val2 pos
    return (Bool result)
  AbsCanela.EAnd pos expr1 expr2 -> do
    (Bool b1) <- evalBool expr1 pos
    (Bool b2) <- evalBool expr2 pos
    return (Bool $ b1 && b2)
  AbsCanela.EOr pos expr1 expr2 -> do
    (Bool b1) <- evalBool expr1 pos
    (Bool b2) <- evalBool expr2 pos
    return (Bool $ b1 || b2)

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
