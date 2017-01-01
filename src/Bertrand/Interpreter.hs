{-# LANGUAGE TupleSections #-}

module Bertrand.Interpreter
    (evalShow,
    )where

import Prelude hiding (read)
import Control.Monad
import Control.Monad.State
import Data.Either
import Data.List
import qualified Data.Map as Map
import Data.Maybe
import Data.Monoid
import Data.Tree

import Bertrand.Data

import Debug.Trace


--------------------------------------------------------------------------------
data Envir = Envir Ref [Expr] Binds
           | Root
    deriving Show

type Binds = Map.Map String [Expr]

instance Monoid Envir where
    mempty = Root
    Root `mappend` e = e
    e `mappend` Root = e
    Envir r xs as `mappend` Envir s ys bs | r == s
                     = Envir r (xs <> ys) (as <> bs)


declares :: Envir -> [Expr]
declares  Root          = []
declares (Envir _ es _) = es
binds :: Envir -> Binds
binds     Root          = Map.empty
binds    (Envir _ _ bs) = bs


type Interpreter a b = a -> State (Memory Envir) b

type Evaluator = Ref -> Interpreter Expr Expr

interpret :: Interpreter a b -> Memory Envir -> a -> b
interpret f s a = let (b, s') = runState (f a) s
                  in traceShow s' b

emapM :: Interpreter Expr Expr -> Interpreter Expr Expr
emapM f (Cons s as)  = Cons s <$> mapM f as
emapM f (App a b)    = do a' <- f a
                          b' <- f b
                          return $ App a' b'
emapM f (Lambda a b) = do a' <- f a
                          b' <- f b
                          return $ Lambda a' b'
emapM f (Bind s a)   = Bind s <$> f a
emapM f (Comma as)   = Comma <$> mapM f as
emapM f (Decl ds a)  = do ds' <- mapM f ds
                          a' <- f a
                          return $ Decl ds' a'
emapM f (Env r a)    = Env r <$> f a
emapM f a            = return a


new :: Interpreter Envir Ref
new env = do
    m <- get
    let (m', ref) = newMemory env m
    put m'
    return ref

read :: Interpreter Ref Envir
read ref = do
    m <- get
    return $ readMemory ref m

write :: (Envir -> Envir) -> Interpreter Ref ()
write f ref = do
    m <- get
    put $ writeMemory f ref m

--------------------------------------------------------------------------------

evalShow :: Expr -> String
evalShow = let (m, ref) = singleton Root
           in show . interpret (\e -> do
               a <- envir ref e
            --    traceShow a return ()
               as <- repeatM (evalStep ref) 5 a
               return $ trace (unlines $ map show $ init as) last as) m

           --


envir :: Ref -> Interpreter Expr Expr
envir r (Decl [] a) = envir r a
envir r (Decl ds a) = do
    let (bs, es) = partition (\x -> case x of Bind _ _ -> True
                                              _        -> False) ds
        -- bds = foldr (\(Bind s a) -> Map.insertWith (++) s [a]) Map.empty bs
    ref <- new $ Envir r es $ toBinds bs
    es' <- mapM (envir ref) es
    write (\(Envir r _ ys) -> Envir r es' ys) ref
    Env ref <$> envir ref a
envir r a = emapM (envir r) a

toBinds :: [Expr] -> Binds
toBinds = foldr (\(Bind s a) -> Map.insertWith (++) s [a]) Map.empty

evalStep :: Evaluator
-- eval r (Var s)
evalStep r e = case e of
    -- Var s     -> commaWith e . concatMap (Map.findWithDefault [] s . binds) <$> envirs r
    Var s -> commaWith e . concatMap ((\(r, es) -> map (Env r) es) . lookupName s)
             <$> envirs r

    -- App (Env r' a') b -> evalStep r' (App a' b)
    App a b -> do
         as <- toList <$> evalTillLambda r a
         let cs = map (`appCons` b) (filter isCons as)
         ls    <- applyTree r (lambdaTree $ filter isLambda as , b)
        --  ls    <- mapM (\l -> apply r (l, b)) (filter isLambda as)
         return $ Comma $ cs ++ ls
        --  return $ Comma $ map (`appCons` b)   (filter isCons as)
        --                ++ map (`appLambda` b) (filter isLambda as)
    -- --              a' <- evalTillLambda r a
    -- --              case a' of
    -- --                  Lambda c d -> match

    Env _ (Env ref a) -> evalStep r $ Env ref a

    Env ref a | r == ref  -> evalStep ref a
              | otherwise -> Env ref <$> evalStep ref a

    Cons s es -> Cons s <$> mapM (evalStep r) es

    Comma [e] -> evalStep r e
    Comma es  -> Comma <$> mapM (evalStep r) (nub es)

    _ -> return e

    where
        commaWith :: Expr -> [Expr] -> Expr
        commaWith e []  = e
        commaWith _ [e] = e
        commaWith _ es  = Comma es

        lookupName :: String -> (Ref, Envir) -> (Ref, [Expr])
        lookupName s = mapSnd $ concat . Map.lookup s . binds

        toList :: Expr -> [Expr]
        toList (Env r e)  = Env r `map` toList e
        toList (Comma es) = es
        toList e          = [e]

        -- hideEnv :: Expr -> Expr
        -- hideEnv (Env r a) = hideEnv $ emap (Env r) a
        -- hideEnv a = a

        isLambda :: Expr -> Bool
        isLambda (Env _ a)    = isLambda a
        isLambda (Lambda _ _) = True
        isLambda _            = False

        isCons :: Expr -> Bool
        isCons (Env _ a)  = isCons a
        isCons (Cons _ _) = True
        isCons _          = False

        appCons :: Expr -> Expr -> Expr
        appCons a b = let (f, Cons s as) = detachEnv a
                      in  Cons s $ map f as ++ [b]
        -- appCons (Cons s es) e = Cons s $ es ++ [e]

        lambdaTree :: [Expr] -> Forest Expr
        -- lambdaTree = map (`Node` [])
        lambdaTree es = let as = map (`Node` []) es
                        in trace (drawForest $ map (fmap show) as) as

        applyTree :: Ref -> Interpreter (Forest Expr, Expr) [Expr]
        applyTree r (xs, e) = concat <$> mapM
            (\(Node a bs) -> apply r (a, e) >>=
                             maybe (return [])
                                   (\x -> defaultl x <$> applyTree r (bs, e))
            ) xs

        -- applyTree :: Forest Expr -> Expr
        -- applyTree = Comma . concatMap
        --             (\(Node a xs) -> maybe [] (defaultl a $ applyTree xs) apply  )
            where
                defaultl :: a -> [a] -> [a]
                defaultl a [] = [a]
                defaultl _ as = as

        apply :: Ref -> Interpreter (Expr, Expr) (Maybe Expr)
        -- apply r (a, b) = undefined
        -- apply :: Ref -> Interpreter (Expr, Expr) Expr
        apply r (a, b) = case a of
            Env r' a'  -> apply r' (a', Env r b)
            -- Lambda c d -> return (Just d)
            Lambda c d -> fmap (maybe d (`Env` d)) <$> match r (c, b)

        match :: Ref -> Interpreter (Expr, Expr) (Maybe (Maybe Ref))
        match r t = do
            m <- match' r t
            maybe (return Nothing) (\es ->
                case es of
                    [] -> return $ Just Nothing
                    _  -> do
                        r' <- new (Envir r [] $ toBinds es)
                        return $ Just $ Just r'
                  ) m

            where
                match' :: Ref -> Interpreter (Expr, Expr) (Maybe [Expr])
                match' r t = let
                    (a, b) = t
                    (ra, a') = detachRef r a
                    -- (rb, b') = detachRef r b
                    in case (a', b) of
                    (App _ _, _) -> do
                        (ra', a'') <- detachRef r <$> evalTillTerm r a
                        case a'' of
                            App _ _ -> return Nothing
                            _       -> match' r (a'', b)

                    (Cons xs as, _) -> do
                        (rb, b') <- detachRef r <$> evalTillCons r b
                        case b' of
                            Cons ys bs | xs == ys && length as == length bs -> do
                                ms <- mapM (match' r) $ zip (map (Env ra) as) (map (Env rb) bs)
                                if Nothing `elem` ms
                                then return Nothing
                                else return $ Just $ concat $ catMaybes ms
                            _ -> return Nothing

                    (Bytes i, Bytes j) | i == j -> return $ Just []

                    (Comma as, _) -> do
                        ms <- mapM (match' r . (, b) . Env ra) as
                        if any isJust ms
                        then return $ Just $ concat $ catMaybes ms
                        else return Nothing

                    (Var s, _) -> return $ Just [Bind s b]


                    (a, b) -> trace "failed" return Nothing

                evalTillTerm :: Evaluator
                evalTillTerm r a = evalStep r a >>=
                    (\a' -> if a == a'
                            then return a
                            else case snd $ detachRef r a' of
                                App _ _ -> evalTillTerm r a'
                                _       -> return a )

                evalTillCons :: Evaluator
                evalTillCons r a = evalStep r a >>=
                    (\a' -> let (r', b) = detachRef r a' in case b of
                        Cons _ _    -> return a'
                        Comma as    -> do
                            as' <- mapM (evalTillLambda r') as
                            return $ Env r' $ Comma as'
                        _ | a == a' -> return a
                        _           -> evalTillCons r a')


        detachRef :: Ref -> Expr -> (Ref, Expr)
        detachRef _ (Env r a) = case a of
            Env _ _ -> detachRef r a
            _       -> (r, a)
        detachRef r a = (r, a)

        detachEnv :: Expr -> (Expr -> Expr, Expr)
        detachEnv (Env r a) = case a of
            Env _ _ -> detachEnv a
            _       -> (Env r, a)
        detachEnv a = (id, a)

        ref :: Ref -> Expr -> Ref
        ref r e = fst $ detachRef r e


        evalTillLambda :: Evaluator
        evalTillLambda r a = let (r', b) = detachRef r a in case b of
            Var _ -> do
                a' <- evalStep r a
                if a == a' then return a'
                           else evalTillLambda r a'
            -- Env _ _ -> evalStep r e >>= evalTillLambda r
            App _ _  -> evalStep r a >>= evalTillLambda r
            Comma as -> do
                as' <- mapM (evalTillLambda r') as
                return $ Env r' $ Comma as'
            _ -> return a

        exprs :: Expr -> [Expr]
        exprs (Comma es) = es
        exprs (Env r a)  = Env r <$> exprs a
        exprs a          = [a]

    --     bindsTree :: [Expr] -> Tree Expr
    --     bindsTree = Node

envirs :: Interpreter Ref [(Ref, Envir)]
envirs r = read r >>= \e -> case e of
    Root            -> return [(r, Root)]
    Envir ref es bs -> ((r, e):) <$> envirs ref

--------------------------------------------------------------------------------

mapSnd :: (b -> c) -> (a, b) -> (a, c)
mapSnd f (a, b) = (a, f b)

tmap :: (a -> b) -> (a, a) -> (b, b)
tmap f (a, b) = (f a, f b)

repeatM :: Monad m => (a -> m a) -> Int -> a -> m [a]
repeatM f i a
    | i <= 0 = return []
    | otherwise = do
        a' <- f a
        as <- repeatM f (i - 1) a'
        return $ a' : as
