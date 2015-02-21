{-# LANGUAGE DeriveGeneric, DeriveDataTypeable, DeriveFunctor, DeriveTraversable, DeriveFoldable #-}

module Conjure.Language.AbstractLiteral where

-- conjure
import Conjure.Prelude
import Conjure.Bug
import Conjure.Language.Name
import Conjure.Language.Domain
import Conjure.Language.Type
import Conjure.Language.AdHoc

import Conjure.Language.TypeOf
import Conjure.Language.Pretty


data AbstractLiteral x
    = AbsLitTuple [x]
    | AbsLitRecord [(Name, x)]
    | AbsLitVariant (Maybe [(Name, Domain () x)]) Name x            -- Nothing before name resolution
    | AbsLitMatrix (Domain () x) [x]
    | AbsLitSet [x]
    | AbsLitMSet [x]
    | AbsLitFunction [(x, x)]
    | AbsLitRelation [[x]]
    | AbsLitPartition [[x]]
    deriving (Eq, Ord, Show, Data, Functor, Traversable, Foldable, Typeable, Generic)

instance Serialize x => Serialize (AbstractLiteral x)
instance Hashable  x => Hashable  (AbstractLiteral x)
instance ToJSON    x => ToJSON    (AbstractLiteral x) where toJSON = genericToJSON jsonOptions
instance FromJSON  x => FromJSON  (AbstractLiteral x) where parseJSON = genericParseJSON jsonOptions

instance Pretty a => Pretty (AbstractLiteral a) where
    pretty (AbsLitTuple xs) = (if length xs < 2 then "tuple" else prEmpty) <+> prettyList prParens "," xs
    pretty (AbsLitRecord xs) = "record" <+> prettyList prBraces "," [ pretty n <+> "=" <+> pretty x
                                                                    | (n,x) <- xs ]
    pretty (AbsLitVariant _ n x) = "variant" <+> prBraces (pretty n <+> "=" <+> pretty x)
    pretty (AbsLitMatrix index xs) = let f i = prBrackets (i <> ";" <+> pretty index) in prettyList f "," xs
    pretty (AbsLitSet       xs ) =                prettyList prBraces "," xs
    pretty (AbsLitMSet      xs ) = "mset"      <> prettyList prParens "," xs
    pretty (AbsLitFunction  xs ) = "function"  <> prettyListDoc prParens "," [ pretty a <+> "-->" <+> pretty b | (a,b) <- xs ]
    pretty (AbsLitRelation  xss) = "relation"  <> prettyListDoc prParens "," [ pretty (AbsLitTuple xs)         | xs <- xss   ]
    pretty (AbsLitPartition xss) = "partition" <> prettyListDoc prParens "," [ prettyList prBraces "," xs      | xs <- xss   ]

instance (TypeOf a, Pretty a) => TypeOf (AbstractLiteral a) where

    typeOf   (AbsLitTuple        []) = return (TypeTuple (replicate 100 TypeAny))
    typeOf   (AbsLitTuple        xs) = TypeTuple    <$> mapM typeOf xs

    typeOf   (AbsLitRecord       xs) = TypeRecord   <$> sequence [ do t <- typeOf x ; return (n,t)
                                                                 | (n,x) <- xs ]

    typeOf   (AbsLitVariant Nothing  _ _) = fail "Cannot calculate the type of variant literal."
    typeOf   (AbsLitVariant (Just t) _ _) = fmap TypeVariant $ forM t $ \ (n,d) -> do
        dt <- typeOf d
        return (n, dt)

    typeOf   (AbsLitMatrix _   []  ) = return (TypeMatrix TypeAny TypeAny)
    typeOf p@(AbsLitMatrix ind inn ) = TypeMatrix   <$> typeOf ind <*> (homoType (pretty p) <$> mapM typeOf inn)

    typeOf   (AbsLitSet         [] ) = return (TypeSet TypeAny)
    typeOf p@(AbsLitSet         xs ) = TypeSet      <$> (homoType (pretty p) <$> mapM typeOf xs)

    typeOf   (AbsLitMSet        [] ) = return (TypeMSet TypeAny)
    typeOf p@(AbsLitMSet        xs ) = TypeMSet     <$> (homoType (pretty p) <$> mapM typeOf xs)

    typeOf   (AbsLitFunction    [] ) = return (TypeFunction TypeAny TypeAny)
    typeOf p@(AbsLitFunction    xs ) = TypeFunction <$> (homoType (pretty p) <$> mapM (typeOf . fst) xs)
                                                    <*> (homoType (pretty p) <$> mapM (typeOf . snd) xs)

    typeOf   (AbsLitRelation    [] ) = return (TypeRelation (replicate 100 TypeAny))
    typeOf p@(AbsLitRelation    xss) = do
        ty <- homoType (pretty p) <$> mapM (typeOf . AbsLitTuple) xss
        case ty of
            TypeTuple ts -> return (TypeRelation ts)
            _ -> bug "expecting TypeTuple in typeOf"

    typeOf   (AbsLitPartition   [] ) = return (TypePartition TypeAny) 
    typeOf p@(AbsLitPartition   xss) = TypePartition <$> (homoType (pretty p) <$> mapM typeOf (concat xss))

normaliseAbsLit :: (Ord c, ExpressionLike c) => (c -> c) -> AbstractLiteral c -> AbstractLiteral c
normaliseAbsLit norm (AbsLitTuple     xs ) = AbsLitTuple                           $ map norm xs
normaliseAbsLit norm (AbsLitRecord    xs ) = AbsLitRecord                          $ map (second norm) xs
normaliseAbsLit norm (AbsLitVariant t n x) = AbsLitVariant t n (norm x)
normaliseAbsLit norm (AbsLitMatrix d  xs ) = AbsLitMatrix (normaliseDomain norm d) $ map norm xs
normaliseAbsLit norm (AbsLitSet       xs ) = AbsLitSet                   $ sortNub $ map norm xs
normaliseAbsLit norm (AbsLitMSet      xs ) = AbsLitMSet                  $ sort    $ map norm xs
normaliseAbsLit norm (AbsLitFunction  xs ) = AbsLitFunction              $ sortNub [ (norm x, norm y) | (x, y) <- xs ]
normaliseAbsLit norm (AbsLitRelation  xss) = AbsLitRelation              $ sortNub $ map (map norm) xss
normaliseAbsLit norm (AbsLitPartition xss) = AbsLitPartition             $ sortNub $ map (sortNub . map norm) xss
