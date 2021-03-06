{-# LANGUAGE LambdaCase #-}

module Bertrand.System
    (systemIds, prelude) where

import Bertrand.Data

systemIds :: [(String, SystemType)]
systemIds = map (\(Func s f) -> (s, Func s f)) [
    funcInt2Int "intadd" (+),
    funcInt2Int "intsub" (-),
    funcInt2Int "intmul" (*),
    funcInt1 "intminus" (\x -> System $ Int (-x)),
    funcInt2 "intcompare" intcompare]
    where
        funcInt1 :: String -> (Integer -> Expr) -> SystemType
        funcInt1 s f =
            Func s $ \case
                Int x -> Just $ f x
                _     -> Nothing

        funcInt2Int :: String -> (Integer -> Integer -> Integer) -> SystemType
        funcInt2Int s f = funcInt2 s (\x y -> System . Int $ f x y)

        funcInt2 :: String -> (Integer -> Integer -> Expr) -> SystemType
        funcInt2 s f =
            Func s $ \case
                Int x -> Just $ System $ Func (s ++ "'") $ \case
                    Int y -> Just $ f x y
                    _ -> Nothing
                _ -> Nothing

        intcompare :: Integer -> Integer -> Expr
        intcompare x y = case compare x y of
            LT -> Id "less"
            EQ -> Id "equal"
            GT -> Id "greater"

prelude :: String
prelude = unlines [
    "infixr 0 =",
    "infixr 1 $",
    "infixf 2 =>",
    "infixr 3 or",
    "infixr 4 and",
    "infixf 5 ==",
    "infixf 5 /=",
    "infixf 5 <=",
    "infixf 5 <",
    "infixf 5 >=",
    "infixf 5 >",
    "infixr 6 :",
    "infixr 6 ++",
    "infixl 7 +",
    "infixl 7 -",
    "infixl 8 *",
    "infixl 8 /",
    "infixl 10 .",

    "var true false undefined",
    "true.true",
    "false.~false",

    "~~true",

    "cons and or",
    "true and true",
    "~(false and _)",
    "~(_ and false)",
    "true or _",
    "_ or true",
    "~(false or false)",

    "ternary _true  = true",
    "ternary _false = false",
    "ternary _      = undefined",

    "a == b = (a = b) and (b = a)",
    "a /= b = ~ (a == b)",

    "x > y = #intcompare x y = greater",

    "comma (x:[]) = x",
    "comma (x:xs) = a ! a = x; a = comma xs",

    -- Basic function

    "id x = x",
    "const x _ = x",
    "f $ x = f x",

    -- -- Arithmetic

    "(+) = #intadd",
    "(-) = #intsub",
    "(*) = #intmul",

    "(-) = #intminus",

    "x > y  = #intcompare x y = greater",
    "x >= y = (#intcompare x y = greater) or (#intcompare x y = equal)",
    "x < y  = #intcompare x y = less",
    "x <= y = (#intcompare x y = less) or (#intcompare x y = equal)",

    -- List
    "head (x:_) = x",
    "tail (_:xs) = xs",
    "last (x:[]) = x",
    "last (_:xs) = last xs",
    "init (x:_:[]) = [x]",
    "init (x:xs)   = x : init xs",
    "null [] = true",
    "null xs = false",
    "length []     = 0",
    "length (_:xs) = length xs + 1",
    "[]     ++ ys = ys",
    "(x:xs) ++ ys = x:(xs ++ ys)",
    "map _ []     = []",
    "map f (x:xs) = f x : map f xs",
    "foldl _ a []     = a",
    "foldl f a (x:xs) = foldl f (f a x) xs",
    "foldr f z []     = z",
    "foldr f z (x:xs) = f x (foldr f z xs)",
    "concat = foldr (++) []",
    "take _ []     = []",
    "take 0 _      = []",
    "take i (x:xs) = x : take (i - 1) xs",
    "drop _ []     = []",
    "drop 0 xs     = xs",
    "drop i (_:xs) = drop (i - 1) xs",

    ""]
