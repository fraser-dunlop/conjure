{-# LANGUAGE TupleSections #-}

module Conjure.Process.Enums
    ( removeEnumsFromModel
    , removeEnumsFromParam
    , addEnumsAndUnnamedsBack
    ) where

import Conjure.Prelude
import Conjure.Bug
import Conjure.UserError
import Conjure.Language.Definition
import Conjure.Language.Domain
import Conjure.Language.Pretty

-- text
import Data.Text as T ( pack )


-- | The argument is a model before nameResolution.
--   Only intended to work on problem specifications.
removeEnumsFromModel :: (MonadFail m, MonadLog m, MonadUserError m) => Model -> m Model
removeEnumsFromModel =
    removeEnumsFromModel_LettingEnums >=>
    removeEnumsFromModel_GivenEnums   >=>
    checkEnums

    where

        removeEnumsFromModel_LettingEnums model = do
            (statements', (enumDomainNames, nameToIntMapping)) <-
                flip runStateT ([], []) $ forM (mStatements model) $ \ st ->
                    case st of
                        Declaration (LettingDomainDefnEnum ename names) -> do
                            namesBefore <- gets (map fst . snd)
                            let outDomain = mkDomainIntB 1 (fromInt (genericLength names))
                            case names `intersect` namesBefore of
                                [] -> modify ( ( [(ename, outDomain)]
                                             , zip names allNats
                                             ) `mappend` )
                                repeated -> userErr1 $ vcat
                                    [ "Some members of this enum domain (" <> pretty ename <> ") seem to be defined"
                                    , "as part of other enum domains."
                                    , "Repeated:" <+> prettyList id "," repeated
                                    , "While working on domain:" <+> pretty st
                                    ]
                            return (Declaration (Letting ename (Domain outDomain)))
                        _ -> return st

            let
                onX :: Monad m => Expression -> m Expression
                onX (Reference nm Nothing)
                    | Just i <- lookup nm nameToIntMapping
                    = return (fromInt i)
                onX p = return p

                onD :: MonadFail m => Domain () Expression -> m (Domain () Expression)
                onD (DomainEnum nm (Just ranges) _)
                    | Just _ <- lookup nm enumDomainNames
                    = DomainInt <$> mapM (mapM (nameToX nameToIntMapping)) ranges
                onD (DomainEnum nm Nothing _)
                    | Just d <- lookup nm enumDomainNames
                    = return (DomainReference nm (Just d))
                onD (DomainReference nm Nothing)
                    | Just d <- lookup nm enumDomainNames
                    = return (DomainReference nm (Just d))
                onD p = return p

            statements'' <- (transformBiM onD >=> transformBiM onX) statements'
            return model { mStatements = statements'' }

        removeEnumsFromModel_GivenEnums model = do
            (statements', enumDomainNames) <-
                flip runStateT [] $ forM (mStatements model) $ \ st ->
                    case st of
                        Declaration (GivenDomainDefnEnum name) -> do
                            let nameS      = name `mappend` "_EnumSize"
                            let outDomainS = DomainInt []
                            let outDomain  = mkDomainIntB 1
                                                (Reference nameS (Just (Alias (Domain outDomainS))))
                            modify ([(name, outDomain)] `mappend`)
                            return [ Declaration (FindOrGiven Given nameS         outDomainS)
                                   , Declaration (Letting           name  (Domain outDomain))
                                   ]
                        _ -> return [st]

            let
                onD :: Domain () Expression -> Domain () Expression
                onD (DomainEnum nm (Just ranges) _)
                    | Just _ <- lookup nm enumDomainNames
                    = DomainInt ranges
                onD (DomainEnum      nm Nothing _)
                    | Just d <- lookup nm enumDomainNames
                    = DomainReference nm (Just d)
                onD (DomainReference nm Nothing)
                    | Just d <- lookup nm enumDomainNames
                    = DomainReference nm (Just d)
                onD p = p

            let model' = model { mStatements = concat statements'
                                    |> transformBi onD
                               }

            logDebug $ "Recording enumGivens:" <+> prettyList id "," (map fst enumDomainNames)

            return model'

        checkEnums model = do
            let
                leftovers :: [Domain () Expression]
                leftovers = [ d | d@DomainEnum{} <- universeBi (mStatements model) ]
            unless (null leftovers) $ bug $ vcat
                $ "Could not remove some enum domains:"
                : map (nest 4 . pretty) leftovers
            return model


removeEnumsFromParam
    :: (MonadFail m, MonadUserError m)
    => Model -> Model -> m (Model, Model)
removeEnumsFromParam model param = do
    let allStatements = map (False,) (map Declaration (miEnumLettings (mInfo model)))
                     ++ map (True,)  (mStatements param)

    (statements', (enumDomainNames, nameToIntMapping)) <-
        flip runStateT ([], []) $ forM allStatements $ \ (keep,st) ->
            case st of
                Declaration (LettingDomainDefnEnum ename names) -> do
                    namesBefore <- gets (map fst . snd)
                    let outDomain = mkDomainIntB 1 (fromInt (genericLength names))
                    case names `intersect` namesBefore of
                        [] -> modify ( ( [(ename, outDomain)]
                                     , zip names allNats
                                     ) `mappend` )
                        repeated -> userErr1 $ vcat
                            [ "Some members of this enum domain (" <> pretty ename <> ") seem to be defined"
                            , "as part of other enum domains."
                            , "Repeated:" <+> prettyList id "," repeated
                            , "While working on domain:" <+> pretty st
                            ]
                    return (Just (Declaration (Letting ename (Domain outDomain))))
                _ -> return (if keep then Just st else Nothing)

    let
        onX :: Monad m => Expression -> m Expression
        onX (Reference nm Nothing)
            | Just i <- lookup nm nameToIntMapping
            = return (fromInt i)
        onX p = return p

        onD :: MonadFail m => Domain () Expression -> m (Domain () Expression)
        onD (DomainEnum nm (Just ranges) _)
            | Just _ <- lookup nm enumDomainNames
            = DomainInt <$> mapM (mapM (nameToX nameToIntMapping)) ranges
        onD (DomainEnum nm Nothing _)
            | Just d <- lookup nm enumDomainNames
            = return (DomainReference nm (Just d))
        onD (DomainReference nm Nothing)
            | Just d <- lookup nm enumDomainNames
            = return (DomainReference nm (Just d))
        onD p = return p

    let param' = param { mStatements = catMaybes statements' }
    let f = transformBiM onD >=> transformBiM onX
    (,) <$> f model <*> f param'


-- | Using the original domains from the Essence file.
--   Converting integers back to enum constants.
-- TODO: complete addEnumsAndUnnamedsBack

addEnumsAndUnnamedsBack
    :: ( Pretty r, Pretty x )
    => [Name]                           -- unnamed types
    -> [((Integer, Name), Constant)]    -- a lookup table for enums
    -> Domain r x                       -- the domain we are working on
    -> Constant                         -- the constant with ints in place of enums & unnameds
    -> Constant                         -- the constant with enums & unnameds again
addEnumsAndUnnamedsBack unnameds ctxt = helper

    where

        helper domain constant = case (domain, constant) of

            (_, c@ConstantUndefined{}) -> c

            (DomainBool  , c) -> c
            (DomainIntE{}, c) -> c
            (DomainInt{} , c) -> c

            (DomainEnum      ename _ _, ConstantInt i) ->
                fromMaybe (bug $ "addEnumsAndUnnamedsBack 1:" <+> pretty (i, ename))
                          (lookup (i, ename) ctxt)

            (DomainReference ename _  , ConstantInt i) ->
                if ename `elem` unnameds
                    then ConstantEnum ename [] (mconcat [ename, "_", Name (T.pack (show i))])
                    else ConstantInt i -- assume this was an int if if is not in the unnameds list

            (DomainTuple ds, ConstantAbstract (AbsLitTuple cs)) ->
                ConstantAbstract $ AbsLitTuple
                    [ helper d c
                    | (d,c) <- zip ds cs ]

            (DomainRecord ds, ConstantAbstract (AbsLitRecord cs)) ->
                ConstantAbstract $ AbsLitRecord
                    [ (n, helper d c)
                    | ((n,d),(_,c)) <- zip ds cs ]

            (DomainVariant ds, ConstantAbstract (AbsLitVariant t n c)) ->
                case lookup n ds of
                    Nothing -> bug $ "addEnumsAndUnnamedsBack Variant:" <++> vcat [ "domain  :" <+> pretty domain
                                                                                  , "constant:" <+> pretty constant
                                                                                  ]
                    Just d  -> ConstantAbstract $ AbsLitVariant t n (helper d c)

            (DomainMatrix _ inner, ConstantAbstract (AbsLitMatrix index vals)) ->
                ConstantAbstract $ AbsLitMatrix index $ map (helper inner) vals

            (DomainSet _ _ inner, ConstantAbstract (AbsLitSet vals)) ->
                ConstantAbstract $ AbsLitSet $ map (helper inner) vals

            (DomainMSet _ _ inner, ConstantAbstract (AbsLitMSet vals)) ->
                ConstantAbstract $ AbsLitMSet $ map (helper inner) vals

            (DomainFunction _ _ fr to, ConstantAbstract (AbsLitFunction vals)) ->
                ConstantAbstract $ AbsLitFunction
                    [ (helper fr a, helper to b)
                    | (a,b) <- vals ]

            (DomainSequence _ _ inner, ConstantAbstract (AbsLitSequence vals)) ->
                ConstantAbstract $ AbsLitSequence $ map (helper inner) vals

            (DomainRelation _ _ inners, ConstantAbstract (AbsLitRelation vals)) ->
                ConstantAbstract $ AbsLitRelation
                    [ [ helper d c | (d,c) <- zip inners line ]
                    | line <- vals ]

            (DomainPartition _ _ inner, ConstantAbstract (AbsLitPartition vals)) ->
                ConstantAbstract $ AbsLitPartition
                    [ [ helper inner c | c <- line ]
                    | line <- vals ]

            _ -> bug ("addEnumsAndUnnamedsBack 3:" <++> vcat [ "domain  :" <+> pretty domain
                                                             , "constant:" <+> pretty constant
                                                             ])

nameToX :: MonadFail m => [(Name, Integer)] -> Expression -> m Expression
nameToX nameToIntMapping (Reference nm _) = case lookup nm nameToIntMapping of
    Nothing -> fail (pretty nm <+> "is used in a domain, but it isn't a member of the enum domain.")
    Just i  -> return (fromInt i)
nameToX _ x = return x
