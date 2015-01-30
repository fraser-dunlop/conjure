{-# LANGUAGE DeriveGeneric, DeriveDataTypeable #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts, FlexibleInstances #-}
{-# LANGUAGE ViewPatterns #-}

module Conjure.Language.Definition
    ( forgetRepr, rangesInts
    , freshNames
    , languageEprime
    , initInfo
    , allContextsExceptReferences

    , quantifiedVar, lambdaToFunction

    , e2c

    , Model(..), LanguageVersion(..)
    , ModelInfo(..), Decision(..)
    , Statement(..), Objective(..)
    , Declaration(..), FindOrGiven(..)

    , Name(..)
    , Expression(..), ReferenceTo(..)
    , Constant(..)
    , AbstractLiteral(..)
    , AbstractPattern(..)
    , GeneratorOrCondition(..), Generator(..), generatorPat

    , ExpressionLike(..), ReferenceContainer(..)

    , extractLettings
    , tupleLitIfNeeded
    , patternToExpr

    ) where

-- conjure
import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Pretty
import Conjure.Language.AdHoc

import Conjure.Language.Name
import Conjure.Language.Constant
import Conjure.Language.AbstractLiteral
import Conjure.Language.Type
import Conjure.Language.Domain
import Conjure.Language.Ops
import Conjure.Language.TypeOf

-- aeson
import Data.Aeson ( (.=), (.:) )
import qualified Data.Aeson as JSON
import qualified Data.Aeson.Types as JSON

-- text
import qualified Data.Text as T

-- uniplate
import Data.Generics.Uniplate.Zipper ( Zipper, down, right, hole )


------------------------------------------------------------------------------------------------------------------------
-- Model ---------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Model = Model
    { mLanguage :: LanguageVersion
    , mStatements :: [Statement]
    , mInfo :: ModelInfo
    }
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

type ModelZipper = Zipper Model Expression

instance Serialize Model
instance Hashable  Model
instance ToJSON    Model where toJSON = genericToJSON jsonOptions
instance FromJSON  Model where parseJSON = genericParseJSON jsonOptions

instance Default Model where
    def = Model def [] def

instance Pretty Model where
    pretty (Model lang stmts info) = vcat $ concat
        [ [pretty lang]
        , [""]
        , map pretty stmts
        , [""]
        , [pretty info | info /= def]
        ]

freshNames :: Model -> [Name]
freshNames model = newNames
    where
        newNames = [ Name name
                   | i <- allNats
                   , let name = "q" `mappend` stringToText (show i)
                   , not (or [name `T.isPrefixOf` usedName | Name usedName <- usedNames])
                   ]
        usedNames = universeBi model :: [Name]

languageEprime :: Model -> Model
languageEprime m = m { mLanguage = LanguageVersion "ESSENCE'" [1,0] }

allContextsExceptReferences :: ModelZipper -> [ModelZipper]
allContextsExceptReferences z0 = concatMap subtreeOf (allSiblings z0)
    where
        -- the input has to be the left most
        allSiblings :: ModelZipper -> [ModelZipper]
        allSiblings z = z : maybe [] allSiblings (right z)

        subtreeOf :: ModelZipper -> [ModelZipper]
        subtreeOf z = z : case hole z of
            Reference{} -> []                                       -- don't go through a Reference
            _           -> maybe [] allContextsExceptReferences (down z)

------------------------------------------------------------------------------------------------------------------------
-- LanguageVersion -----------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data LanguageVersion = LanguageVersion Name [Int]
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize LanguageVersion
instance Hashable  LanguageVersion

instance ToJSON LanguageVersion where
    toJSON (LanguageVersion t is) =
        JSON.object [ "language" .= toJSON t
                    , "version"  .= toJSON is
                    ]

instance FromJSON LanguageVersion where
    parseJSON (JSON.Object x) =
        LanguageVersion <$> x .: "language"
                        <*> x .: "version"
    parseJSON x = bug $ "Error while parsing JSON:" <++> pretty (show x)

instance Default LanguageVersion where
    def = LanguageVersion "Essence" [1,3]

instance Pretty LanguageVersion where
    pretty (LanguageVersion language version) =
        "language" <+> pretty language
                   <+> hcat (intersperse "." (map pretty version))


------------------------------------------------------------------------------------------------------------------------
-- Statement -----------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Statement
    = Declaration Declaration
    | SearchOrder [Name]
    | Where [Expression]
    | Objective Objective Expression
    | SuchThat [Expression]
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize Statement
instance Hashable  Statement
instance ToJSON    Statement where toJSON = genericToJSON jsonOptions
instance FromJSON  Statement where parseJSON = genericParseJSON jsonOptions

instance Pretty Statement where
    pretty (Declaration x) = pretty x
    pretty (SearchOrder nms) = "branching on" <++> prettyList prBrackets "," nms
    pretty (Where xs) = "where" <++> vcat (punctuate "," $ map pretty xs)
    pretty (Objective obj x) = pretty obj <++> pretty x
    pretty (SuchThat xs) = "such that" <++> vcat (punctuate "," $ map pretty xs)


------------------------------------------------------------------------------------------------------------------------
-- Objective -----------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Objective = Minimising | Maximising
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize Objective
instance Hashable  Objective
instance ToJSON    Objective where toJSON = genericToJSON jsonOptions
instance FromJSON  Objective where parseJSON = genericParseJSON jsonOptions

instance Pretty Objective where
    pretty Minimising = "minimising"
    pretty Maximising = "maximising"


------------------------------------------------------------------------------------------------------------------------
-- Declaration ---------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Declaration
    = FindOrGiven FindOrGiven Name (Domain () Expression)
    | Letting Name Expression
    | GivenDomainDefnEnum Name
    | LettingDomainDefnEnum Name [Name]
    | LettingDomainDefnUnnamed Name Expression
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize Declaration
instance Hashable  Declaration
instance ToJSON    Declaration where toJSON = genericToJSON jsonOptions
instance FromJSON  Declaration where parseJSON = genericParseJSON jsonOptions

instance Pretty Declaration where
    pretty (FindOrGiven forg nm d) = hang (pretty forg <+> pretty nm <>  ":" ) 8 (pretty d)
    pretty (Letting nm (Domain x)) = hang ("letting" <+> pretty nm <+> "be domain") 8 (pretty x)
    pretty (Letting nm x) = hang ("letting" <+> pretty nm <+> "be") 8 (pretty x)
    pretty (GivenDomainDefnEnum name) =
        hang ("given"   <+> pretty name) 8 "new type enum"
    pretty (LettingDomainDefnEnum name values) =
        hang ("letting" <+> pretty name <+> "be new type enum") 8
             (prettyList prBraces "," values)
    pretty (LettingDomainDefnUnnamed name size) =
        hang ("letting" <+> pretty name <+> "be new type of size") 8 (pretty size)


data FindOrGiven = Find | Given | Quantified | LocalFind
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize FindOrGiven
instance Hashable  FindOrGiven
instance ToJSON    FindOrGiven where toJSON = genericToJSON jsonOptions
instance FromJSON  FindOrGiven where parseJSON = genericParseJSON jsonOptions

instance Pretty FindOrGiven where
    pretty Find = "find"
    pretty Given = "given"
    pretty Quantified = "quantified"
    pretty LocalFind = "find"


------------------------------------------------------------------------------------------------------------------------
-- ModelInfo -----------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data ModelInfo = ModelInfo
    { miGivens :: [Name]
    , miFinds :: [Name]
    , miEnumGivens :: [Name]
    , miEnumLettings :: [Declaration]
    , miUnnameds :: [(Name, Expression)]
    , miOriginalDomains :: [(Name, Domain () Expression)]
    , miRepresentations :: [(Name, Domain HasRepresentation Expression)]
    , miTrailCompact :: [(Int,[Int])]
    , miTrailVerbose :: [Decision]
    }
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

modelInfoJSONOptions :: JSON.Options
modelInfoJSONOptions = jsonOptions { JSON.fieldLabelModifier = onHead toLower . drop 2 }
    where onHead f (x:xs) = f x : xs
          onHead _ [] = []

instance Serialize ModelInfo
instance Hashable  ModelInfo
instance ToJSON    ModelInfo where toJSON = genericToJSON modelInfoJSONOptions
instance FromJSON  ModelInfo where parseJSON = genericParseJSON modelInfoJSONOptions

instance Default ModelInfo where
    def = ModelInfo def def def def def def def def def

instance Pretty ModelInfo where
    pretty = commentLines . pretty . toJSON
        where
            commentLines :: Doc -> Doc
            commentLines
                = vcat                          -- Doc
                . map ("$ " `mappend`)          -- comment each line
                . ("Conjure's" :)               -- add the heading
                . map pretty                    -- [Doc]
                . lines                         -- [String]
                . renderNormal                  -- to String

initInfo :: Model -> Model
initInfo model = model { mInfo = info }
    where
        info = (mInfo model)
            { miGivens = [ nm | Declaration (FindOrGiven Given nm _) <- mStatements model ]
            , miFinds  = [ nm | Declaration (FindOrGiven Find  nm _) <- mStatements model ]
            , miOriginalDomains =
                [ (nm, dom)
                | Declaration (FindOrGiven _ nm dom) <- mStatements model
                ]
            , miEnumGivens   = [ nm     | Declaration (GivenDomainDefnEnum nm)         <- mStatements model ]
            , miEnumLettings = [ d      | Declaration d@LettingDomainDefnEnum{}        <- mStatements model ]
            , miUnnameds     = [ (nm,s) | Declaration (LettingDomainDefnUnnamed nm s)  <- mStatements model ]
            }


------------------------------------------------------------------------------------------------------------------------
-- Decision ------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Decision = Decision
    { dDescription :: [Text]
    , dOptions :: [Int]
    , dDecision :: Int
    }
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

decisionJSONOptions :: JSON.Options
decisionJSONOptions = jsonOptions { JSON.fieldLabelModifier = map toLower . drop 1 }

instance Serialize Decision
instance Hashable  Decision
instance ToJSON    Decision where toJSON = genericToJSON decisionJSONOptions
instance FromJSON  Decision where parseJSON = genericParseJSON decisionJSONOptions


------------------------------------------------------------------------------------------------------------------------
-- Expression ----------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data Expression
    = Constant Constant
    | AbstractLiteral (AbstractLiteral Expression)
    | Domain (Domain () Expression)
    | Reference Name (Maybe ReferenceTo)
    | WithLocals Expression [Statement]
    | Comprehension Expression [GeneratorOrCondition]
    | Typed Expression Type
    | Op (Ops Expression)
    | ExpressionMetaVar String
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize Expression
instance Hashable  Expression
instance ToJSON    Expression where toJSON = genericToJSON jsonOptions
instance FromJSON  Expression where parseJSON = genericParseJSON jsonOptions

viewIndexed :: Expression -> (Expression, [Doc])
viewIndexed (Op (MkOpIndexing (OpIndexing m i  ))) =
    let this = pretty i
    in  second (++ [this]) (viewIndexed m)
viewIndexed (Op (MkOpSlicing  (OpSlicing  m a b))) =
    let this = maybe prEmpty pretty a <> ".." <> maybe prEmpty pretty b
    in  second (++ [this]) (viewIndexed m)
viewIndexed m = (m, [])

instance Pretty Expression where

    prettyPrec _ (viewIndexed -> (m,is@(_:_))) = pretty m <> prettyList prBrackets "," is

    -- mostly for debugging: print what a reference is pointing at
    -- prettyPrec _ (Reference x Nothing) = pretty x <> "#`NOTHING`"
    -- prettyPrec _ (Reference x (Just (DeclHasRepr _ _ dom))) = pretty x <> "#`" <> pretty dom <> "`"
    -- prettyPrec _ (Reference x (Just r)) = pretty x <> "#`" <> pretty r <> "`"

    prettyPrec _ (Constant x) = pretty x
    prettyPrec _ (AbstractLiteral x) = pretty x
    prettyPrec _ (Domain x) = "`" <> pretty x <> "`"
    prettyPrec _ (Reference x _) = pretty x
    prettyPrec _ (WithLocals x ss) = vcat [ "{" <+> pretty x
                                          , "@" <+> vcat (map pretty ss)
                                          , "}"
                                          ]
    prettyPrec _ (Comprehension x is) = prBrackets $ pretty x <++> "|" <+> prettyList id "," is
    prettyPrec _ (Typed x ty) = prParens $ pretty x <+> ":" <+> "`" <> pretty ty <> "`"
    prettyPrec prec (Op op) = prettyPrec prec op
    prettyPrec _ (ExpressionMetaVar x) = "&" <> pretty x

instance TypeOf Expression where
    typeOf (Constant x) = typeOf x
    typeOf (AbstractLiteral x) = typeOf x
    typeOf (Domain x)   = typeOf x
    typeOf (Reference nm Nothing) = fail ("Type error, identifier not bound:" <+> pretty nm)
    typeOf (Reference nm (Just refTo)) =
        case refTo of
            Alias x -> typeOf x
            InComprehension gen ->
                let
                    lu pat ty = maybe
                        (bug $ vcat ["Type error, InComprehension:", pretty nm, pretty pat, pretty ty])
                        return
                        (lu' pat ty)
                    lu' (Single nm') ty | nm == nm' = Just ty
                    lu' (AbsPatTuple  pats) (TypeTuple    tys) = zipWith lu' pats tys   |> catMaybes |> listToMaybe
                    lu' (AbsPatMatrix pats) (TypeMatrix _ ty ) = [lu' p ty | p <- pats] |> catMaybes |> listToMaybe
                    lu' (AbsPatSet    pats) (TypeSet      ty ) = [lu' p ty | p <- pats] |> catMaybes |> listToMaybe
                    lu' _ _ = Nothing
                in
                    case gen of
                        GenDomainNoRepr  pat domain -> typeOf domain                 >>= lu pat
                        GenDomainHasRepr pat domain -> typeOf domain                 >>= lu (Single pat)
                        GenInExpr        pat expr   -> typeOf expr   >>= innerTypeOf >>= lu pat
            DeclNoRepr  _ _ dom -> typeOf dom
            DeclHasRepr _ _ dom -> typeOf dom
    typeOf (WithLocals x _) = typeOf x                  -- TODO: do this properly, looking into locals and other ctxt
    typeOf (Comprehension x _) = TypeList <$> typeOf x  -- TODO: do this properly, look into generators and filters
    typeOf (Typed _ ty) = return ty
    typeOf (Op op) = typeOf op
    typeOf x@ExpressionMetaVar{} = bug ("typeOf:" <+> pretty x)

instance CanBeAnAlias Expression where
    isAlias (Reference _ (Just (Alias x))) = Just x
    isAlias _ = Nothing

instance OperatorContainer Expression where
    injectOp = Op
    projectOp (Op op) = return op
    projectOp x = na ("Not an operator:" <++> pretty (show x))

instance ReferenceContainer Expression where
    fromName nm = Reference nm Nothing

instance ExpressionLike Expression where
    fromInt = Constant . fromInt
    intOut (Constant c) = intOut c
    intOut x = fail ("Expecting a constant, but got:" <+> pretty x)
    fromBool = Constant . fromBool
    boolOut (Constant c) = boolOut c
    boolOut x = fail ("Expecting a constant, but got:" <+> pretty x)

instance Num Expression where
    x + y = Op $ MkOpPlus    $ OpPlus [x,y]
    x - y = Op $ MkOpMinus   $ OpMinus x y
    x * y = Op $ MkOpTimes   $ OpTimes [x,y]
    abs x = Op $ MkOpTwoBars $ OpTwoBars x
    signum _ = bug "signum {Expression}"
    fromInteger = fromInt . fromInteger

instance Integral Expression where
    divMod a b = ( Op $ MkOpDiv $ OpDiv a b
                 , Op $ MkOpMod $ OpMod a b )
    quotRem = divMod
    toInteger = bug "toInteger {Expression}"

instance Real Expression where
    toRational = bug "toRational {Expression}"

instance Enum Expression where
    fromEnum = bug "fromEnum {Expression}"
    toEnum = fromInt
    succ a = a + 1
    pred a = a - 1
    enumFrom x = x : enumFrom (succ x)
    enumFromThen x n = x : enumFromThen (x+n) n
    enumFromTo _x _y = bug "enumFromTo {Expression}"
    enumFromThenTo _x _n _y = bug "enumFromThenTo {Expression}"

e2c :: Expression -> Constant
e2c (Constant c) = c
e2c x = bug ("e2c, not a constant:" <+> pretty x)

quantifiedVar :: Name -> (AbstractPattern, Expression)
quantifiedVar nm =
    let pat = Single nm
        ref = Reference nm Nothing
    in  (pat, ref)


lambdaToFunction :: AbstractPattern -> Expression -> Expression -> Expression
lambdaToFunction (Single nm) body = \ p ->
    let
        replacer :: Expression -> Expression
        replacer (Reference n _) | n == nm = p
        replacer x = x
    in
        transform replacer body
lambdaToFunction (AbsPatTuple ts) body = \ p ->
    let
        unroll :: [AbstractPattern] -> [Expression] -> Expression -> Expression
        unroll [] [] b = b
        unroll (pat:pats) (val:vals) b = unroll pats vals (lambdaToFunction pat b val)
        unroll _ _ _ = bug "lambdaToFunction, AbsPatTuple, unroll"

        ps :: [Expression]
        ps = case p of
            Constant (ConstantAbstract (AbsLitTuple xs)) -> map Constant xs
            AbstractLiteral (AbsLitTuple xs) -> xs
            _ -> [ Op (MkOpIndexing (OpIndexing p i))
                 | i' <- take (length ts) allNats
                 , let i = fromInt i'
                 ]
    in
        unroll ts ps body
lambdaToFunction (AbsPatMatrix ts) body = \ p ->
    let
        unroll :: [AbstractPattern] -> [Expression] -> Expression -> Expression
        unroll [] [] b = b
        unroll (pat:pats) (val:vals) b = unroll pats vals (lambdaToFunction pat b val)
        unroll _ _ _ = bug "lambdaToFunction, AbsPatMatrix, unroll"

        ps :: [Expression]
        ps = case p of
            Constant (ConstantAbstract (AbsLitMatrix _ xs)) -> map Constant xs
            AbstractLiteral (AbsLitMatrix _ xs) -> xs
            _ -> bug "lambdaToFunction, AbsPatMatrix"
    in
        unroll ts ps body
lambdaToFunction (AbsPatSet ts) body = \ p ->
    let
        unroll :: [AbstractPattern] -> [Expression] -> Expression -> Expression
        unroll [] [] b = b
        unroll (pat:pats) (val:vals) b = unroll pats vals (lambdaToFunction pat b val)
        unroll _ _ _ = bug "lambdaToFunction, AbsPatSet, unroll"

        ps :: [Expression]
        ps = case p of
            Constant (ConstantAbstract (AbsLitSet xs)) -> map Constant xs
            AbstractLiteral (AbsLitSet xs) -> xs
            _ -> bug "lambdaToFunction, AbsPatSet"
    in
        unroll ts ps body
lambdaToFunction p@AbstractPatternMetaVar{} _ = bug $ "Unsupported AbstractPattern, got " <+> pretty (show p)


------------------------------------------------------------------------------------------------------------------------
-- ReferenceTo ---------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data ReferenceTo
    = Alias           Expression
    | InComprehension Generator
    | DeclNoRepr      FindOrGiven Name (Domain () Expression)
    | DeclHasRepr     FindOrGiven Name (Domain HasRepresentation Expression)
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize ReferenceTo
instance Hashable  ReferenceTo
instance ToJSON    ReferenceTo where toJSON = genericToJSON jsonOptions
instance FromJSON  ReferenceTo where parseJSON = genericParseJSON jsonOptions

instance Pretty ReferenceTo where
    pretty (Alias           x  ) = "Alias"           <+> prParens (pretty x)
    pretty (InComprehension gen) = "InComprehension" <+> prParens (pretty gen)
    pretty (DeclNoRepr      forg nm dom) = "DeclNoRepr"  <+> prParens (pretty forg <+> pretty nm <> ":" <+> pretty dom)
    pretty (DeclHasRepr     forg nm dom) = "DeclHasRepr" <+> prParens (pretty forg <+> pretty nm <> ":" <+> pretty dom)


------------------------------------------------------------------------------------------------------------------------
-- AbstractPattern -----------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data AbstractPattern
    = Single Name
    | AbsPatTuple [AbstractPattern]
    | AbsPatMatrix
            -- (Domain () a)          -- TODO: Should there be a domain here?
            [AbstractPattern]
    | AbsPatSet [AbstractPattern]
    -- | AbsPatMSet [a]
    -- | AbsPatFunction [(a, a)]
    -- | AbsPatRelation [[a]]
    -- | AbsPatPartition [[a]]
    -- TODO: Consider introducing the above as abstract patterns...
    | AbstractPatternMetaVar String
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Serialize AbstractPattern
instance Hashable  AbstractPattern
instance ToJSON    AbstractPattern where toJSON = genericToJSON jsonOptions
instance FromJSON  AbstractPattern where parseJSON = genericParseJSON jsonOptions

instance Pretty AbstractPattern where
    pretty (Single       nm) = pretty nm
    pretty (AbsPatTuple  xs) = (if length xs <= 1 then "tuple" else prEmpty) <>
                               prettyList prParens   "," xs
    pretty (AbsPatMatrix xs) = prettyList prBrackets "," xs
    pretty (AbsPatSet    xs) = prettyList prBraces "," xs
    pretty (AbstractPatternMetaVar s) = "&" <> pretty s

patternToExpr :: AbstractPattern -> Expression
patternToExpr (Single nm) = Reference nm Nothing
patternToExpr (AbsPatTuple  ts) = AbstractLiteral $ AbsLitTuple  $ map patternToExpr ts
patternToExpr (AbsPatMatrix ts) = AbstractLiteral $ AbsLitMatrix (DomainInt [RangeBounded 1 (fromInt (length ts))])
                                                                 $ map patternToExpr ts
patternToExpr (AbsPatSet    ts) = AbstractLiteral $ AbsLitSet    $ map patternToExpr ts
patternToExpr AbstractPatternMetaVar{} = bug "patternToExpr"

------------------------------------------------------------------------------------------------------------------------
-- Generator -----------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

data GeneratorOrCondition = Generator Generator | Condition Expression
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Pretty GeneratorOrCondition where
    pretty (Generator x) = pretty x
    pretty (Condition x) = pretty x

instance Serialize GeneratorOrCondition
instance Hashable  GeneratorOrCondition
instance ToJSON    GeneratorOrCondition where toJSON = genericToJSON jsonOptions
instance FromJSON  GeneratorOrCondition where parseJSON = genericParseJSON jsonOptions


data Generator
     = GenDomainNoRepr  AbstractPattern (Domain () Expression)
     | GenDomainHasRepr Name            (Domain HasRepresentation Expression)
     | GenInExpr        AbstractPattern Expression
    deriving (Eq, Ord, Show, Data, Typeable, Generic)

instance Pretty Generator where     
    pretty (GenDomainNoRepr  pat x) = pretty pat <+> ":"  <+> pretty x
    pretty (GenDomainHasRepr pat x) = pretty pat <+> ":"  <+> pretty x
    pretty (GenInExpr        pat x) = pretty pat <+> "<-" <+> pretty x

instance Serialize Generator
instance Hashable  Generator
instance ToJSON    Generator where toJSON = genericToJSON jsonOptions
instance FromJSON  Generator where parseJSON = genericParseJSON jsonOptions

generatorPat :: Generator -> AbstractPattern
generatorPat (GenDomainNoRepr  pat _) = pat
generatorPat (GenDomainHasRepr pat _) = Single pat
generatorPat (GenInExpr        pat _) = pat


------------------------------------------------------------------------------------------------------------------------
-- Misc ---------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

extractLettings :: Model -> [(Name, Expression)]
extractLettings model =
    [ (n, x) | Declaration (Letting n x) <- mStatements model
             , not (isDomain x)
             ]
    where isDomain Domain{} = True
          isDomain _ = False


tupleLitIfNeeded :: [Expression] -> Expression
tupleLitIfNeeded [] = bug "tupleLitIfNeeded []"
tupleLitIfNeeded [x] = x
tupleLitIfNeeded xs = AbstractLiteral (AbsLitTuple xs)