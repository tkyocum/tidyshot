# Suite marks for the D lines

Each of the 293 D lines in `catalogue.json` was checked by opening the test it names in `TidyShotTests` and reading
its body. Of those, 288 get a mark below and the other 5 go to the "not covered after all" list at the end, all as
C. The reconciliation of the four documents (critic.md) added five D lines, each checked the same way: four that
obsolete-E.md moves from E to D (phase-2 52, phase-3 28, 32 and 67) and phase-3-1 55, which moves from A to D with
phase-3 28 because one guard covers both. It also turned four full marks into in-part ones (phase-4a 38, phase-4c
202, recording-r1 298 and recording-r2 308) and named the tests behind recording-r2 614. That makes 293 marks: 195
`(suite: …)` and 98 `(suite, in part: …)`. Below the phase-3 list is the mark for the D half of phase-3 26, an A
line; it is not counted among the 293.

How to use it: append the mark to the end of the checklist item (after its last continuation line). On a
confirm-or-overrule line, put it before the `______` blank, as R4 :372-376 do; the blank stays Tim's. An in-part
mark says after the `;` what stays by hand. Test names follow the R4 form, `Suite.test` then `.otherTest` for more
tests in the same suite. Every name was checked against the test sources.

A mark is full when what stays by hand is only the gesture that sets the case up (a drag, a shortcut, a real
capture). It is "in part" when a rule the line states rests on a view, on NSLog, on coordinator glue behind a
deferred seam, or on a real device or bucket, and no test reads it.

Eighteen recording-r4 lines already carry a mark. Their bullets say "already marked", with "keep" or a replacement:
238 and 240 get new text, the other sixteen stand.

## coordinator-harness

Every line here is a confirm-or-overrule call: the mark says what the suite pins, and the blank (`______`) stays
Tim's on every line. Put the mark before the blank, as R4 :372-376 do.

- 43: (suite, in part: CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld; that `.live()` and `shared` are unchanged stays a code read)
- 44: (suite, in part: CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld, CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing; that the live types conform unchanged stays a code read)
- 45: (suite, in part: CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld; `download(key:)` has no coordinator test, and the signatures are a code read)
- 47: (suite, in part: CoordinatorDeleteTests.anAbortThatFindsNothingIsNotRepeatedAndLogsItGone, CoordinatorRecoveryTests.aZeroByteFileIsRemoved; the live `NSLog("%@", …)` sink and `RecordingLog.note` staying are a code read)
- 48: (suite, in part: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; no `private` member opened and `record()` not driven are a code read)
- 54: (suite: CoordinatorDeleteTests.anAbortThatFindsNothingIsNotRepeatedAndLogsItGone, UploadQueueTests.aSinglePutJobsAbortThatFindsNothingIsLoggedAsGone, .aMultipartJobsAbortThatFindsNothingIsLoggedAsGone)
- 55: (suite: UploadQueueTests.aPartAddedAfterACancelSendsNothing, .aNewUploadWhoseFirstSidecarCannotBeWrittenIsAborted)
- 63: (suite: CoordinatorRecoveryTests.anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing, .aZeroByteFileIsRemoved)
- 65: (suite: CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination; the ruling itself is Tim's to write)
- 67: (suite: CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink)

## phase-2

- 11: (suite, in part: S3DestinationConfigTests.validation; the shown text and the red stay by hand: no test reads the error's message)
- 13: (suite, in part: AppSettingsTests.s3ConfigRoundTripsThroughDefaults, KeychainCredentialStoreTests.keychainStoreRoundTrips; the form filling its fields at relaunch stays by hand)
- 14: (suite, in part: KeychainCredentialStoreTests.keychainStoreRoundTrips; the form turning a cleared field into no token stays by hand)
- 15: (suite, in part: S3DestinationConfigTests.paddedFieldsAreTrimmedNotRejected; the field showing the trimmed name and a real upload stay by hand)
- 18: (suite, in part: ConnectionTesterTests.readableWhenPutSucceedsAndPublicGetReturnsBody, .readableSummaryDoesNotEchoTheProbeURL; the real bucket removing the probe stays by hand)
- 20: (suite, in part: ConnectionTesterTests.uploadFailedWhenPutIsRejected; the `Upload failed: ` summary text and a real 403 stay by hand)
- 21: (suite, in part: ConnectionTesterTests.notPublicWhenGetIsForbidden, .wrongBodyOn200IsNotReadable, .unexpectedStatusOnPublicGetIsReportedDistinctly; the test reads only `HTTP 403` in the summary, so the rest of the text and a real wrong domain stay by hand)
- 29: (suite, in part: ImageEncoderTests.retinaScaleWrites144DPI; that the uploaded object is that PNG from a real Retina capture stays by hand)
- 31: (suite, in part: S3DestinationTests.aclHeaderIsSentAndSignedWhenEnabled, .fileUploadSignsCacheControlAndACL; the real bucket accepting the ACL and the object being public stay by hand)
- 35: (suite, in part: S3DestinationConfigTests.pathStyleURLWithPortForMinIO, S3DestinationTests.headUsesPathStyleAndPortedHost; a real MinIO accepting the upload stays by hand)
- 50: (suite: CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem, UploadRefusalTests.retryFailedUploadsLeavesOutMarkedAndDeletingRecords)
- 52: (suite: RecentCaptureFormattingTests.nameIsTheObjectOrTheFileName, .detailIsTheRelativeTimeAndAnUnsettledState, .detailIsTheTimeAndTheSize, .detailIsTheTimeTheSizeAndEachUploadState) Moved from E by obsolete-E; put the mark on obsolete-E's corrected text (rows show the name, the relative time, the size and the upload state in words). The tests pin every string a row shows, none with an emoji.
- 53: (suite: HistoryStoreTests.uploadingRecordsBecomeFailedOnLoadAndPersist, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard)
- 54: (suite: UploadQueueTests.doesNotRetryClientErrors, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, QuickAccessModelTests.failedShowsTheMessage)
- 55: (suite: HistoryStoreTests.addPersistsAndReloadsNewestFirst)
- 56: (suite: HistoryStoreTests.corruptFileIsSetAsideNotOverwritten)

## phase-3

- 28: (suite: CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing) Moved from E by obsolete-E. It duplicates phase-3-1 55 and takes the same mark. The test holds the second Delete at the first alert, not during the storage request; the `deletingIDs` guard it reaches is set at AppCoordinator+Delete.swift:22 and cleared in the defer at :27-30, so it holds through the request too, and only the Network Link Conditioner setup stays by hand.
- 32: (suite, in part: CoordinatorDeleteTests.aSharedKeyKeepsTheObjectAndSaysSo, S3DestinationTests.headTreats403AsMissing; a real key that cannot read objects answering 403 for an existing key, so that two captures land on one key, stays by hand) Moved from E by obsolete-E; use its corrected text ("Delete the first from its row").
- 47: (suite: HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded, CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination)
- 52: (suite, in part: S3DestinationConfigTests.phase2PrefixAndLengthMigrateToTemplate, .roundTripsThroughJSON, ObjectKeyNamerTests.migratedTemplateFromPhase2Settings; the Upload tab showing the template stays by hand, and the line's `defaults read` cannot show encoded data: use the `plutil … | base64 -D` form from the Phase 3.1 checklist)
- 58: (suite, in part: FileNamerTests.yearMonthDayAndHostnameTokens, .defaultTemplateMatchesSystemStyle; that a real save names its file from the template stays by hand)
- 67: (suite, in part: HistoryStoreTests.corruptFileIsSetAsideNotOverwritten, .corruptFileSetAsideSurvivesNameCollision, CoordinatorRecoveryTests.anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing, .anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice, .aZeroByteFileIsRemoved; `start()` running the load and then the adoption at launch is not driven, and `thumbnails/` left untouched and the menu's `No captures yet` stay by hand) Moved from E by obsolete-E; put the mark on obsolete-E's corrected text.

The D half of an A line, not counted above:

- 26: the alert text `... The uploaded object stays in the bucket.` is pinned by CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays. The line is A (obsolete-E moves it from E): its coordinator half, no DELETE for a record without a location and the row and file gone, is tests-A's new CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest. Once that test exists the line's one mark is (suite: CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays, CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest).

## phase-3-1

- 27: (suite, in part: RecentCaptureFormattingTests.nameIsTheObjectOrTheFileName, .detailIsTheRelativeTimeAndAnUnsettledState, ThumbnailProviderTests.legacyRecordGetsAThumbnailGeneratedOnceAndStored; the row's look with its thumbnail stays by hand)
- 42: (suite: ThumbnailProviderTests.previewComesFromTheFileOrFallsBackToTheThumbnail)
- 48: (suite: CaptureDeletionTests.confirmationTextIsOneLine, .confirmationTextSaysWhenTheObjectStays)
- 55: (suite: CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing) Moved from A: the catalogue had it as A, and tests-A.md withdrew the new test it planned. The test holds the second Delete at the first alert; the `deletingIDs` guard (AppCoordinator+Delete.swift:16, set at :22, cleared in the defer at :27-30) holds through the storage request too, so the overlay's and the row's trash both return at once while the request hangs. phase-3 28 takes the same mark.
- 58: (suite, in part: AppSettingsTests.storedTemplatesLoseTheRemovedAppToken, ObjectKeyNamerTests.literalFoldersAndTokens; the upgrade over a real Phase 3 container, the two Settings tabs and the real upload's key stay by hand)

## phase-4a

- 38: (suite, in part: EditorInputTests.retainedWinsForLatestCapture; the coordinator keeping `latestCapture` through an upload-only upload, so the record's id is the retained one, is not driven and stays by hand)
- 40: (suite, in part: EditorWindowGeometryTests.cascadeOffsetsAndStaysOnScreen; that it cascades from the front editor (`NSApp.orderedWindows`) stays by hand)
- 59: (suite: CanvasToolTests.transientUpdatesDuringDrag, .shiftViaFlagsChangedSquares, .optionDrawsFromCentre, .commitOnMouseUpOnly, .tinyDragDiscarded, .newShapeSelected, EditorModelTests.selectAllAndCancelOnlyChangeSelection, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- 61: (suite: EditorModelTests.sliderBurstOnSelectedBlurIsOneStep, RedactionRendererTests.blurTileEqualsFullImageBlurCrop, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- 63: (suite: CanvasToolTests.arrowShiftSnaps45, ArrowGeometryTests.headSymmetricAboutShaft)
- 64: (suite, in part: CanvasToolTests.selectPicksTopmost, .moveCommitsOnceWithDelta, .shiftLocksMoveAxis, .handleDragResizes, .clickEmptyDeselects, HitTesterTests.resizedByEachOfEightHandles, .arrowEndpointHandlesMoveEnds, EditorModelTests.deleteSelectionCommitsOnce, .selectAllAndCancelOnlyChangeSelection, KeyRoutingTests.nudgeOneOrTenPixels; the dashed outline's look stays by hand)
- 72: (suite, in part: RedactionExportTests.redactRegionHoldsOnlyFillAfterPNGRoundTrip, .pixelateRegionIsBlockUniformAndDiffersFromSource, .blurRegionDiffersFromSource; the suite runs at scale 2 only, so the 1x display run and judging the blur unreadable stay by hand)
- 73: (suite, in part: ImageEncoderTests.retinaScaleWrites144DPI, .standardScaleWrites72DPI, RedactionExportTests.outsideEffectsEqualBaseAndScaleIsTwo; that a real 1x capture saves at scale 1 stays by hand)
- 74: (suite: RedactionExportTests.blurOverRedactLeaksNoSourcePixel, RedactionRendererTests.blurOverEarlierRedactBlursBlack, .blurNextToRedactSamplesRedactInMargin)
- 75: (suite: RedactionTileCacheTests.movingEarlierEffectRerendersOverlappingLater)
- 76: (suite: RedactionRendererTests.alphaZeroCornerStaysZero, EditorFlattenerTests.alphaZeroCornerKept)
- 79: (suite: EditorModelTests.twoCommitsTwoUndos, .undoRestoresSnapshotAndRedoReapplies, KeyRoutingTests.shortcutTableMatchesExpectedChords)
- 80: (suite: EditorModelTests.coalescedNudgesAreOneStep, .undoRestoresSnapshotAndRedoReapplies, KeyRoutingTests.nudgeOneOrTenPixels)
- 81: (suite: EditorModelTests.differentCoalescingKeyStartsNewStep, .coalescedNudgesAreOneStep)
- 82: (suite: EditorModelTests.sliderBurstOnSelectedBlurIsOneStep)
- 83: (suite: EditorModelTests.selectionAndZoomNotUndone, .applyColorToSelectionIsUndoable)
- 84: (suite, in part: EditorModelTests.hasUnsavedChangesFollowsMarkSavedAndUndo; the window's dot following the model stays by hand)
- 87: (suite: EditorWindowGeometryTests.clampedToNinetyPercent, CanvasTransformTests.fittingNeverExceedsNaturalSize, .fittingCentres)
- 125: (suite, in part: UploadQueueTests.fixedKeyPassesCacheControl, S3DestinationTests.cacheControlHeaderIsSignedWhenSet, .noCacheControlByDefault; `startUpload` building the replace with `no-cache` has no test, and what `curl` sees on the real bucket stays by hand)
- 154: (suite, in part: EditorSaveTargetTests.closeSheetSaveButton; the button opening the save panel stays by hand)
- 156: (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)

## phase-4b

- 34: (suite: EditorModelTests.makeAnnotationUsesToolSettingsInImagePixels, .selectAllAndCancelOnlyChangeSelection, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen, EditorFlattenerTests.ellipseStrokePixels, CanvasToolTests.ellipseShiftMakesCircleAndLineSnapsTo45, .optionDrawsFromCentre, .shiftViaFlagsChangedSquares, .commitOnMouseUpOnly, .tinyDragDiscarded, HitTesterTests.ellipseHitOnRingNotCentre)
- 35: (suite: HitTesterTests.ellipseHitOnRingNotCentre, .effectSelectableOutsideDrawing, CanvasToolTests.handleDragResizes)
- 36: (suite: EditorFlattenerTests.lineStrokePixels, CanvasToolTests.ellipseShiftMakesCircleAndLineSnapsTo45, .newShapeSelected, HitTesterTests.lineHitWithinWidth)
- 42: (suite: CanvasToolTests.tinyOrCancelledStrokeLeavesNothing, EditorModelTests.strokeToolsKeepTheirOwnColourAndWidth)
- 43: (suite, in part: HitTesterTests.strokeHitWithinWidth, AnnotationDocumentTests.strokesMoveRecolourAndRoundTrip, CanvasToolTests.moveCommitsOnceWithDelta, SelectionOutlineTests.earlierKindsAreUnchanged, EditorModelTests.deleteSelectionCommitsOnce; the dashed outline's look stays by hand)
- 46: (suite: EditorModelTests.strokeToolsKeepTheirOwnColourAndWidth, KeyRoutingTests.digitsOneToSixPickWidths)
- 54: (suite: KeyRoutingTests.digitsPickTextSizesForTextTool, EditorModelTests.reEditReplacesInPlaceAndBlankDeletes)
- 59: (suite: EditorModelTests.textEditCommitsOnceWithoutEditorUndo, .reEditReplacesInPlaceAndBlankDeletes, .twoCommitsTwoUndos)
- 69: (suite: EditorModelTests.undoRestoresUncropped, .undoOfAnUnrelatedStepKeepsTheCropDraft, CropGeometryTests.readoutCountsExportedPixels)
- 70: (suite: CropGeometryTests.flattenedSizeEqualsCrop)
- 78: (suite: RedactionExportTests.croppedExportKeepsRedactionAndHasCropSize)
- 81: (suite: EditorModelTests.escapeCancelsCropAndAnotherToolApplies)
- 89: (suite: CanvasToolTests.optionDragDuplicates, .optionReleasedMidDragMoves)
- 117: (suite: EditorModelTests.selectAllAndCancelOnlyChangeSelection, .selectAllFallsBackToASpotlight, .deleteSelectionCommitsOnce, .undoRestoresUncropped)
- 119: (suite: HitTesterTests.topmostPrefersDrawingOverEffectBeneath, .effectSelectableOutsideDrawing, .ellipseHitOnRingNotCentre, CanvasToolTests.selectPicksTopmost)

## phase-4c

- 101: (suite, in part: CanvasToolTests.spotlightDragCommitsAddSpotlight, HitTesterTests.spotlightHandlesResizeItsRect, SpotlightRenderingTests.overlappingSpotlightsLeaveTheirUnionUndimmed; the dashed outline's look stays by hand)
- 104: (suite: CanvasToolTests.shiftViaFlagsChangedSquares, .spotlightDragCommitsAddSpotlight, EditorModelTests.aNewSpotlightTakesTheShapeDefault)
- 105: (suite: CanvasToolTests.optionDrawsFromCentre, .spotlightDragCommitsAddSpotlight)
- 106: (suite: EditorModelTests.aNewSpotlightTakesTheShapeDefault, SpotlightRenderingTests.outsideIsDimmedAndInsideIsNot)
- 107: (suite: SpotlightRenderingTests.eachDimDarkensByItsAmount, .outsideIsDimmedAndInsideIsNot)
- 109: (suite: KeyRoutingTests.nudgeOneOrTenPixels, EditorModelTests.coalescedNudgesAreOneStep, AnnotationDocumentTests.spotlightAndCounterBoundsAndMove)
- 116: (suite: SpotlightRenderingTests.anOpaqueBaseMatchesANormalComposite)
- 122: (suite: HitTesterTests.anArrowInsideASpotlightIsHitFirst, .aRedactionInsideASpotlightIsHit, AnnotationDocumentTests.spotlightsAreAThirdList, CanvasToolTests.textInsideASpotlightIsReEdited)
- 123: (suite, in part: HitTesterTests.bareImageInsideASpotlightHitsItsBody, .anEllipseSpotlightIsHitInsideItsEllipseOnly, .spotlightHandlesResizeItsRect, .handlesBeforeBody, EditorModelTests.selectAllAndCancelOnlyChangeSelection; the closing "a drag from there resizes it" does not hold for an unselected spotlight: `SelectTool.mouseDown` resizes only from the selection's handles, so that drag moves it. Fix the line to say "once selected", or check by hand)
- 124: (suite: EditorModelTests.selectAllFallsBackToASpotlight)
- 127: (suite: SpotlightRenderingTests.theCropIsAppliedAfterTheOverlay)
- 134: (suite, in part: EditorModelTests.shapeAndDimEnableRules, .sizeEnableRule; `Line width` enabled and the blur radius and pixel block rules are the view's `.disabled` modifiers, which no test reads, so they stay by hand)
- 135: (suite: EditorModelTests.shapeAndDimEnableRules, AnnotationDocumentTests.documentWithoutSpotlightDimReadsHalf, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- 136: (suite, in part: EditorModelTests.aRunOfDimClicksIsOneStep, .shapeAndDimOnASelectedSpotlightAreOneStepEach, .dimWithoutASpotlightOrUnchangedAddsNoStep; the title's edited mark following the model stays by hand)
- 137: (suite: EditorModelTests.dimWithoutASpotlightOrUnchangedAddsNoStep, .shapeAndDimEnableRules)
- 138: (suite, in part: EditorModelTests.shapeAndDimOnASelectedSpotlightAreOneStepEach, .shapeWithNothingSelectedChangesOnlyTheDefault; whether the reshape after drawing surprises you stays yours to write)
- 139: (suite, in part: EditorModelTests.sizeEnableRule, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen; the `Small`, `Medium`, `Large` labels are not asserted and stay by hand)
- 141: (suite: EditorModelTests.colorAppliesRule, .aSelectedCounterShowsAndTakesTheColour)
- 142: (suite, in part: ToolOptionsViewTests.everyToolKeepsOneLinePerRow, .aSelectedSpotlightKeepsOneLinePerRow, .thePopoverIsWideEnoughForItsWidestRow; the labels' right alignment stays by hand)
- 145: (suite, in part: CanvasToolTests.counterClickAndDragPlaceAtThePress, EditorModelTests.aNewCounterTakesTheSizeAndColourDefaults, CounterTests.renderedCounterIsFilledAndRinged, .renderedNumberIsCentred, HitTesterTests.counterBodyIsItsCircle; the dashed outline round the bounding square stays by hand)
- 146: (suite: CanvasToolTests.counterClickAndDragPlaceAtThePress, .escapeDuringACounterPressPlacesNothing)
- 147: (suite: CounterTests.nextNumberIsOneMoreThanTheLargest, .duplicateOptionDragAndPasteEachTakeTheNextNumber, CanvasToolTests.counterClickAndDragPlaceAtThePress)
- 148: (suite: CounterTests.centreClampsInsideTheBounds, .renderedCounterIsFilledAndRinged, EditorModelTests.aNewCounterTakesTheSizeAndColourDefaults, CropGeometryTests.pressOutsideAnAppliedCrop)
- 149: (suite: HitTesterTests.counterBodyIsItsCircle, CanvasToolTests.selectPicksTopmost, .clickEmptyDeselects, .moveCommitsOnceWithDelta, .optionReleasedMidDragShowsTheCounterWithItsOwnNumber, EditorModelTests.coalescedNudgesAreOneStep)
- 150: (suite: CounterTests.numberColourContrastsWithEverySwatch, .renderedNumberIsCentred)
- 152: (suite: EditorModelTests.sizeOnASelectedCounterIsOneStepAboutItsCentre, .sizeWithNothingSelectedChangesOnlyTheDefault, .aNewCounterTakesTheSizeAndColourDefaults, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- 154: (suite: CounterTests.numbersFitTheCircle, .nextNumberIsOneMoreThanTheLargest)
- 158: (suite: CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber)
- 160: (suite: CanvasToolTests.optionReleasedMidDragShowsTheCounterWithItsOwnNumber, .optionReleasedMidDragMoves, CounterTests.nextNumberIsOneMoreThanTheLargest)
- 161: (suite: CounterTests.threePastesOfOneCounterCascade)
- 168: (suite: EditorModelTests.shapeAndDimOnASelectedSpotlightAreOneStepEach, .aRunOfDimClicksIsOneStep, .sizeOnASelectedCounterIsOneStepAboutItsCentre)
- 169: (suite: CanvasToolTests.counterClickAndDragPlaceAtThePress, .optionReleasedMidDragShowsTheCounterWithItsOwnNumber, CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber, EditorModelTests.undoRestoresSnapshotAndRedoReapplies)
- 170: (suite: EditorModelTests.aSelectedCounterShowsAndTakesTheColour, .coalescedNudgesAreOneStep, .deleteSelectionCommitsOnce)
- 171: (suite: EditorModelTests.deleteSelectionCommitsOnce, CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber)
- 182: (suite: SpotlightRenderingTests.outsideIsDimmedAndInsideIsNot, EditorFlattenerTests.bytesOutsideEffectsEqualBase, .displayP3BaseKeepsColourSpace)
- 183: (suite: SpotlightRenderingTests.eachDimDarkensByItsAmount)
- 196: (suite, in part: SpotlightRenderingTests.aTallCaptureIsDimmedTheSameAcrossTheStripSeams, EditorFlattenerTests.aTallBaseIsCopiedExactlyAcrossTheStripSeams; Preview at 400 % and a counter across the seam stay by hand)
- 202: (suite, in part: AppSettingsTests.aStoredCounterSizeOutsideTheStopsReadsAs32; the Size row's `Medium` label is not asserted, as on line 139, and stays by hand)
- 207: (suite: CanvasAccessibilityTests.spotlightsReadBetweenEffectsAndDrawings)
- 208: (suite: CanvasAccessibilityTests.countersReadTheirOwnNumbers)
- 213: (suite: SpotlightRenderingTests.noSpotlightDimsNothing, EditorFlattenerTests.outputSizeEqualsBase, .bytesOutsideEffectsEqualBase)

## phase-5

- 104: (suite, in part: ScrollCaptureSessionTests.tooFastShowsTheLineUntilTheNextMovement, ScrollStitcherTests.tooFastThenRecover; End and Home in a real Safari stay by hand)
- 112: (suite, in part: ScrollCaptureSessionTests.aChangeInPlaceDoesNotShowTheTooFastLine, OverlapFinderTests.aChangeInPlaceIsStillNotLost; real Terminal output stays by hand)
- 126: (suite, in part: ScrollCaptureSessionTests.aChangeInPlaceDoesNotShowTheTooFastLine; a real chat stays by hand)
- 132: (suite, in part: ScrollStitcherTests.outputStopsAtTheCapExactly, .aCapShorterThanTheFirstFrameCutsIt, ScrollStitchEngineTests.theCapEndsTheStitchAtExactlyTheLimit, ScrollCaptureStatusTests.theHeightLimitLineNamesTheLimit; the tests use small caps, so the real 65,536 px file in Preview stays by hand)
- 169: (suite, in part: AutoScrollDriverTests.aPageThatNeverMovesEndsAfterTryingBothDirections; wheel events reaching the pane under the real pointer, and writing down the result, stay by hand)
- 200: (suite: ThumbnailMakerTests.cropForThumbnailKeepsTheTopOfTallImages, .targetSizeFitsTheLongestSide)

## phase-6a

- 77: (suite: AppSettingsTests.overlayStackSettingsDefaultAndPersist, .overlayCloseAfterDragDefaultsOnAndPersists, .freezeScreenDefaultsOffAndPersists, .windowShadowDefaultsOffAndPersists)
- 159: (suite, in part: ClosedOverlaysTests.repeatedRestoresWalkBack, .hasRestorableMatchesPop; the coordinator's `restoreClosedOverlay` showing the card and the menu item's enabled state stay by hand, behind the screen seam)
- 162: (suite, in part: ClosedOverlaysTests.popSkipsDeletedAndShownIds; the coordinator passing the shown cards to it, and the restore itself, stay by hand)
- 163: (suite, in part: ClosedOverlaysTests.popSkipsDeletedAndShownIds; the coordinator's record check and the restore itself stay by hand)
- 213: (suite: PreviousAreaTests.aRectPartlyOffItsDisplayIsClippedToIt, .aRectBetweenTwoDisplaysGoesToTheOneHoldingItsCentre)

## phase-6b

- 47: (suite: AppSettingsTests.allInOneAspectLockDefaultsOffAndPersists, .selfTimerSecondsDefaultsToFiveAndPersists, .urlCommandSettingsRoundTripThroughASecondInstance)
- 58: (suite, in part: AllInOneToolbarPlacementTests.belowTheSelectionAndCentred, .aboveWhenThereIsNoRoomBelow, .insideTheBottomEdgeWhenNeitherFits, .clampedToTheScreensSides; the notch inset read from a real screen's `safeAreaInsets` stays by hand)
- 103: (suite, in part: URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; what each capture then does (the selection, window mode, the display under the pointer, the previous area) is the hotkey path's and stays by hand)
- 106: (suite, in part: URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; the self-timer selection and countdown stay by hand)
- 108: (suite, in part: URLCommandHandlerTests.everyCommandReachesItsCaptureFunction, ClosedOverlaysTests.newestFirst, .popSkipsDeletedAndShownIds; the card coming back is `restoreClosedOverlay` behind the screen seam and stays by hand)
- 109: (suite: URLCommandTests.everyCommandParsesFromThePath, .theSchemeTheCommandAndTheNamesIgnoreCase)
- 110: (suite, in part: CaptureIntentTests.standardIsTheGeneralSettingWithNothingAfter; that the hotkeys and the menu pass `.standard` is a code read, and the capture itself stays by hand)
- 114: (suite: CaptureIntentTests.noActionIsTheAfterCaptureActionInGeneral, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction)
- 119: (suite: URLCommandTests.everyActionParsesOnEveryCaptureCommand, .anUnknownOrEmptyActionIsAnError, .errorMessagesAreTheSpecStrings)
- 126: (suite: URLCommandGeometryTests.aRectPartlyOffItsDisplayIsClipped, .aRectThatLeavesLessThanAPointIsOutside, URLCommandHandlerTests.errorsArePostedAndRunNothing)
- 131: (suite: URLCommandHandlerTests.silentCommandsAreRefusedByDefaultNamingTheSender, URLCommandGateTests.theRefusalNamesTheSenderWhenItIsKnown)
- 132: (suite: URLCommandGateTests.commandsThatWaitForTheUserRunWithTheSecondToggleOff, URLCommandHandlerTests.commandsThatWaitForTheUserRunWithSilentCapturesOff)
- 133: (suite: URLCommandHandlerTests.withURLCommandsOffEveryURLIsRefusedAlike, URLCommandGateTests.withURLCommandsOffEveryCommandIsRefused)
- 149: (suite: URLCommandTests.onlyPlainDecimalsAreNumbers, .widthAndHeightMustBeAboveZero, .hugeAndOverlongNumbersAreRefused, .theRectValuesComeTogetherOrNotAtAll, .errorMessagesAreTheSpecStrings)
- 150: (suite: URLCommandTests.aRepeatedParameterIsAnError, .errorMessagesAreTheSpecStrings)
- 151: (suite: URLCommandTests.percentEncodingIsDecodedBeforeMatching, URLCommandHandlerTests.silentCommandsAreRefusedByDefaultNamingTheSender)
- 154: (suite: URLCommandTests.anUnknownCommandIsAnError, .errorMessagesAreTheSpecStrings)
- 155: (suite: URLCommandTests.parametersACommandDoesNotTakeAreIgnored, .noActionLeavesItToTheAfterCaptureSetting)
- 158: (suite: URLCommandHandlerTests.urlsWaitUntilTheAppHasStartedThenRunInOrder)

## phase-7b

- 80: (suite, in part: SelectionOutcomeTests.areaModeCancelsOnAClickOrATinyDrag; `captureText()` stopping before `copyText` on a cancelled selection is a code read, and the overlay closing stays by hand)
- 82: (suite: URLCommandHandlerTests.commandsThatWaitForTheUserRunWithSilentCapturesOff, .everyCommandReachesItsCaptureFunction, URLCommandTests.parametersACommandDoesNotTakeAreIgnored, .everyCaptureButCaptureTextTakesAnAction)
- 84: (suite, in part: URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused, .theLogSaysWhyACaptureCommandWasDropped, ShortcutsTests.aRefusedCaptureNamesTheRecordingThenTheLockThenThePrompt; the `dropped, a capture is running` line goes to NSLog, which no test reads, so the log stays by hand)
- 105: (suite, in part: DesktopCoverReasonsTests.theEndOfACaptureLeavesPersistent, .captureAndPersistentTogether; `DesktopCoverController.hide` acting on the reasons, and the covers staying after each capture kind, stay by hand)
- 106: (suite, in part: DesktopCoverReasonsTests.persistentOffDuringACaptureKeepsTheCoversUntilTheCaptureEnds, URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused; the controller acting on the reasons during a real countdown stays by hand)
- 122: (suite: URLCommandGateTests.theDesktopIconCommandsNeedOnlyURLCommandsOn, URLCommandHandlerTests.withURLCommandsOffEveryURLIsRefusedAlike, .commandsThatWaitForTheUserRunWithSilentCapturesOff)
- 123: (suite: URLCommandTests.theDesktopIconCommandsParseAndIgnoreParameters, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction)
- 124: (suite: URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused)

## phase-7c

- 70: (suite: AppSettingsTests.windowBackgroundDefaultsOffAndPersists)
- 77: (suite: AppSettingsTests.backgroundStyleIsStoredAsJSONAndRoundTrips)
- 80: (suite: BackgroundStyleTests.aspectTitlesAndRatios)
- 92: (suite, in part: EditorBackgroundExportTests.toggleAndStyleChangeAreEachOneUndoStep; the slider handing its drag to the draft and its release to one commit is view wiring with no test, for Padding and Corner Radius alike, and stays by hand)
- 95: (suite: EditorBackgroundExportTests.solidColourRunIsOneUndoStep)
- 112: (suite: BackgroundCompositorTests.fillImageIsDrawnAspectFillAndCentred)
- 115: (suite: CustomBackgroundStoreTests.storesTheImageAsCustomPNGAndReadsItBack, AppSettingsTests.backgroundStyleIsStoredAsJSONAndRoundTrips)
- 116: (suite, in part: BackgroundCompositorTests.nilFillImageDrawsPresetZero, CustomBackgroundStoreTests.emptyUntilAnImageIsStored; an export or window capture reading the real store after the file is gone stays by hand)
- 129: (suite: BackgroundLayoutTests.paddingAtOneX, .paddingAtTwoX, EditorBackgroundExportTests.solidBackgroundExportHasTheLayoutsSizeAndFill)
- 130: (suite: BackgroundLayoutTests.radiusScalesWithTheCapture, BackgroundCompositorTests.roundedClipLeavesTheCornerToTheFill)
- 131: (suite: BackgroundLayoutTests.radiusIsCappedAtHalfTheShorterSide)
- 132: (suite, in part: BackgroundCompositorTests.shadowDarkensTheFillBelowTheContent, .shadowIsOffsetDownNotUp; the shadow's soft look and its cut-off at Padding 0 stay by hand)
- 138: (suite: BackgroundLayoutTests.autoKeepsTheMinimumCanvas, .paddingAtTwoX)
- 139: (suite: BackgroundLayoutTests.eachRatioGrowsTheHeightOfWideContent, .contentNarrowerThanTheRatioGrowsTheWidth, .paddingCountsBeforeTheRatio)
- 140: (suite: BackgroundLayoutTests.oddSizesCentreWithTheOriginRoundedDown, .contentNarrowerThanTheRatioGrowsTheWidth)
- 141: (suite: BackgroundLayoutTests.portraitContentInvertsTheRatio)
- 142: (suite: BackgroundLayoutTests.eachRatioGrowsTheHeightOfWideContent)
- 163: (suite: EditorBackgroundExportTests.backgroundFramesTheCrop, .shownBackgroundFramesTheCropInImagePixels)
- 194: (suite: EditorWindowGeometryTests.initialSizeUsesTheToolbarMinimum, EditorToolbarTests.measuredToolbarFitsASmallDisplay)

## recording-r1

Lines 331 and 336 are confirm-or-overrule calls: put the mark before the blank, which stays Tim's.

- 123: (suite, in part: DesktopCoverReasonsTests.theEndOfACaptureLeavesPersistent, .captureAndPersistentTogether; the controller keeping the covers up through a real window recording stays by hand)
- 128: (suite: RecordingControllerTests.cancelUnderFiveSecondsRemovesTheFileWithoutAsking, RecordingEndTests.discardingCancelRemovesAPlayableFileAndPostsNothing)
- 131: (suite: RecordingLimitsTests.cancelAsksFromFiveSeconds, RecordingControllerTests.cancelUnderFiveSecondsRemovesTheFileWithoutAsking, .cancelFromFiveSecondsAsksAfterTheWaitAndSaveKeepsTheFileAsStopDoes)
- 132: (suite: RecordingControllerTests.cancelFromFiveSecondsAsksAfterTheWaitAndSaveKeepsTheFileAsStopDoes)
- 251: (suite, in part: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled, .aQuitCancelsTheCountInStopsTheRecordingAndWaitsForTheNotices; `record()` is not driven, so no file, no record and no panel stay by hand)
- 272: (suite, in part: MultipartPlanTests.partSizeIsNilAbove625GiB, RecordingSavePlanTests.oversizedNotice, .oversizedSaveFolderFileStays, .oversizedPendingFileMovesIntoTheSaveFolder; the coordinator's `refuseOversizedUpload` has no test, and the line's hand check is already skipped)
- 276: (suite, in part: CoordinatorUploadTests.anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft, QuickAccessModelTests.uploadedSaysWhetherTheLinkWasCopied; the title `Uploaded, URL copied` is the live notifier's and stays by hand)
- 278: (suite: RecordingSavePlanTests.urlReplacesTheClipboardOnlyWhenItIsUnchanged, CoordinatorUploadTests.anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft)
- 298: (suite, in part: ClopOptimiserTests.notEnoughFreeSpaceSkipsClop; the test asserts the outcome `.original(.notEnoughSpace)` only, so the log text `Clop: not enough free space, uploading the original` (ClopOptimiser.swift:29, logged at AppCoordinator+Upload.swift:456) stays a code read)
- 305: (suite: QuickAccessModelTests.aVideoHasCopyFileInPlaceOfTheImageActions, RecentCaptureFormattingTests.aVideoHasNoImageActions)
- 324: (suite, in part: SaveLocationMoveTests.aClashGetsTheNextNumber; that `saveRecording` places a recording named by the template through it is a code read and stays by hand)
- 331: (suite: RecordingSavePlanTests.uploadWithNoDestinationFallsBackAsSave, .saveFallbackKeepsTheRecordingInPending, .oversizedSaveFolderFileStays, .oversizedPendingFileMovesIntoTheSaveFolder)
- 336: (suite: QuitHoldTests.everyRecordingPhaseButIdleHolds, CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled, RecordingControllerTests.aStartThatThrowsFailsWithItsDescriptionAndNoFile, .startErrorsSayWhatWentWrong)
- 341: (suite: CaptureRecordTests.historyWithoutMediaKindDecodesAsImages)
- 343: (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)

## recording-r2

Lines 612-623 are confirm-or-overrule items: the mark goes before the blank, which stays Tim's. Lines 647-660 are
already ticked with Tim's ruling; the mark only records which test holds the ruled behaviour.

- 197: (suite, in part: RecordingConfigurationTests.aGIFRecordingNeverCapturesAudioAndRecordsAt30FPS, .aGIFRecordingNeverCapturesTheMicrophone, MicrophoneChoiceTests.aGIFStartTreatsAnyStoredMicrophoneAsOff; `afinfo` on a real file and the `Recording: starting …` log line stay by hand)
- 212: (suite, in part: GIFEncoderTests.delaysAreWholeCentisecondsSummingToTheLength, GIFMakerTests.theDelaysSumToTheOutputFramesAndTheGIFLoops; writing down one real GIF's delays stays by hand)
- 216: (suite, in part: GIFEncoderTests.delaysAreWholeCentisecondsSummingToTheLength, GIFMakerTests.aGapIsOneFrameWhoseDelaySpansIt, .aLongHeldStretchIsSplitAtTheMaximumDelay; a real GIF's frame count and size stay by hand)
- 220: (suite, in part: AppSettingsTests.fullSizeGIFsKeepTheRecordingCap, GIFMakerTests.aSmallSourceIsNeverUpscaledAndFullSizeKeepsUpTo4096, RecordingConfigurationTests.outputSizeCapsTheLongerSideAt4096; a real 5K recording and the GIF playing stay by hand)
- 245: (suite, in part: GIFConversionTests.underOneGBFreeNeverMakesAndSavesTheMP4, .runningOutOfSpaceMidWriteGivesTheSameNotice, RecordingControllerTests.underOneGigabyteAtAFiveSecondTickEndsTheRecording, GIFFileSinkTests.lessThan1GBFreeAtA32MBBoundaryThrows; the optional full-disk run and the write-down stay by hand)
- 303: (suite: RecordingControllerTests.aPressBeforeTheFirstFrameOpensAtZero)
- 308: (suite, in part: RecordingControllerTests.aRecordingNeverMutedHasNoLog, MuteLogWriterTests.aWriterNeverGivenALogWritesNothing; the controller test cancels its recording, so for a kept recording with no mute stretches, `endRecording` skipping the mute ladder (AppCoordinator+Recording.swift:636) is not driven and "its audio is untouched" stays by hand)
- 309: (suite, in part: RecordingMuteTests.aFailedApplyRemovesTheSoundInstead, .muteFailureWrapsTheSteps, .soundRemovedHasTheDesignsText, .stripAudioKeepsTheVideoAndDropsTheSound; `muteAndSave` posting the notice, the Debug build's `-MuteFailure` and the `mute failed` log line stay by hand)
- 329: (suite: RecordingMuteTests.tooLittleRoomIsNotMutedWithoutEitherStep)
- 331: (suite: RecordingControllerTests.aDiscardRemovesTheMuteLogOnceTheWriterHasFinished, .cancelFromFiveSecondsWithDiscardRemovesTheFileAndPostsNothing)
- 360: (suite, in part: ShortcutsTests.aRefusedStartPostsOnlyAfterAPrompt; the `Recording: not started after the microphone prompt …` log line is not read by any test)
- 367: (suite: MicrophoneChoiceTests.aMissingDeviceRecordsTheDefaultInputAndSaysSo, .aMissingDeviceWithNoInputRecordsNoMicrophoneAndNamesIt, .systemDefaultWithNoInputRecordsNoMicrophone, RecordingNoticeOrderTests.theSavesNoticeThenRecordingStoppedThenTheMicrophoneNote)
- 370: (suite, in part: MicrophoneChoiceTests.aGIFStartTreatsAnyStoredMicrophoneAsOff, .aGIFStartWithAMissingDeviceRecordsNoMicrophoneAndPostsNothing, .aGIFRecordingDropsTheResolvedInputAndItsNote, .onlyAnMP4WithAMicrophoneSetAsksWhileAccessIsNotDetermined, MicrophoneLatencyTests.noInputReadsNothingAndTakesTheNoMicrophoneLag; the start's log text stays by hand)
- 405: (suite, in part: NoticeHoldTests.aNoticeAskedForWhileNotHoldingPostsAtOnce; the coordinator's own posts after a screenshot's save and `saveRecording` are not driven and stay by hand)
- 420: (suite: RecordingTrimTests.trimShowsForMP4RecordingsOnly, .canTrimIsFalseWhileUploadingDeletingOrTrimming, .menuStateHidesBothForAGIF, QuickAccessModelTests.trimShowsOnlyForAVideoAndIsDisabledWhileUploadingOrDeleting)
- 466: (suite, in part: RecordingTrimTests.aRecordThatStartsUploadingAfterTheWindowOpenedIsRefused, .writePlanRefusesADeletedDeletingOrUploadingRecord; comparing the bucket's object with the local file stays by hand)
- 478: (suite, in part: RecordingTrimTests.closingAWindowRemovesOnlyItsRecordsWorkFiles; `trimWindowDidClose` calling it is behind the Trim window seam and stays by hand)
- 479: (suite, in part: DragFileStoreTests.aCopyIsHandedOutOnlyWhenItMatchesTheRecordsFileNow, .aChangedSourceIsCopiedAgain; `finishTrimWrite` removing the drag folder, the drag-out and Save As stay by hand)
- 481: (suite: RecordingTrimTests.aMarkedRecordsTrimHasItsMutedStretchesSilent, .aMarkedRecordCanBeTrimmed, CaptureRecordTests.aTrimsWriteRecordsTheTrimmedFile)
- 612: (suite: GIFConversionTests.onSuccessTheGIFIsSavedAndTheMP4RemovedOnlyAfterTheRecordExists, .whenTheGIFIsLeftInTmpTheGIFIsRemovedAndTheMP4Stays)
- 614: (suite: GIFConversionTests.makeReadsTheMP4AndWritesTheGIFBesideIt, .onSuccessTheGIFIsSavedAndTheMP4RemovedOnlyAfterTheRecordExists, .onFailureTheMP4IsSavedAsAVideoWithGIFNotMade, RecordingRecoveryTests.aFoundFileWithALogComesBackMutedAndItsLogIsRemoved, .aListedFileWithNoRecordingIsSwept, RecordingMuteTests.applyThenReplaceIsMuted, .soundThatIsNotAACThrowsAndTheLadderRemovesIt) The earlier mark named the bare suite `GIFConversionTests`; the three named here run `GIFConversion` itself, and `soundThatIsNotAACThrowsAndTheLadderRemovesIt` calls `RecordingMute.resolve` with its output URL and duration.
- 618: (suite, in part: MicrophoneChoiceTests.aMicrophoneStartReadsTheAccessFirstAndListsTheInputsOnlyWithIt, RecordingControllerTests.theAppSaysWhichWayTheMicrophoneWasLost; which live object Settings reads is a code read)
- 620: (suite: RecordingControllerTests.anErrorWhileTheMicrophoneIsLostSaysSo, .anErrorWithNoMicrophoneAsksNothing, .theAppSaysWhichWayTheMicrophoneWasLost)
- 623: (suite: RecordingMuteTests.theLogAndTheRewriteLiveInTmpMute, RecordingControllerTests.aRecordingNeverMutedHasNoLog, MuteLogWriterTests.theDefaultWriteMakesTheFolderAndWritesTheLog, .aWriterNeverGivenALogWritesNothing)
- 647: (suite: RecordingNoticeOrderTests.quitModeGivesNothing)
- 657: (suite: RecordingTrimTests.aReencodeHoldsItsLastFrameToTheRangesEnd)
- 658: (suite: RecordingTrimTests.aReencodeWithNoFrameToShowThrowsAndLeavesNoOutput, .aFullDiskReadsDiskFullAndOtherErrorsTheirOwnText)
- 660: (suite: ShortcutsTests.aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen, .aRefusedStartPostsOnlyAfterAPrompt, CoordinatorRecordingTests.anOpenPromptRefusesCapturesUntilItIsAnswered)
- 672: (suite: CaptureRecordTests.historyWithoutUnmutedIntervalsDecodesEmpty, .historyWithoutMediaKindDecodesAsImages, .videoRecordRoundTrips, .everyKindButAnImageIsTimeBased)
- 675: (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)

## recording-r3

Lines 409-441 are confirm-or-overrule items: the mark goes before the blank, which stays Tim's.

- 125: (suite: CameraChoiceTests.aPickOfSystemDefaultStoresIt, .aPickOfAListedCameraStoresItsListedName, .aStoredChoiceGivesBackTheTwoSettings, AppSettingsTests.r3RecordingSettingsPersistUnderTheirKeys)
- 212: (suite: CameraNoteTests.aLossAfterAStartNotePostsNothingMore, CameraChoiceTests.aMissingDeviceTakesThePreferredCameraAndSaysSo)
- 315: (suite: RecordingPanelLayoutTests.areaAndFullscreenBarsAre244And280PointsWide, .theButtonsRunFromTheTimeToCancel, .theGIFTagTakesTheMuteButtonsPlaceBeforeTheTime, .aTimePastAnHourFitsTheTimeFrame, RecordingControllerTests.aRequestWithoutExtrasShowsR2sBars, RecordingConfigurationTests.theMuteButtonShowsOnlyForSystemAudioOrTheMicrophone)
- 318: (suite, in part: RecordingPanelLayoutTests.theBarsAre172And208PointsWide, RecordingControllerTests.aRequestWithoutExtrasShowsR2sBars; that the hand-off gives a window recording no extras is not driven and stays by hand)
- 329: (suite, in part: BubbleButtonStateTests.accessOffSaysSo, .noCameraSaysSo, .notDeterminedAsksForSettings, .enabledWithACameraAuthorizedAccessAndAFilmedWindow, RecordingControllerTests.theBubbleStartsOffAndDisabledWithTheToggleOnAndNoCamera, RecordingPanelLayoutTests.theBubbleButtonShowsItsStateAndSaysWhatAPressDoes; the hand-off building the state from the real camera and access is not driven and stays by hand)
- 334: (suite: CameraNoteTests.noNoteWhenWantedAndAllWentWell, .noNoteWhenTheBubbleWasNeverWanted, RecordingControllerTests.aBubblePressOnMarksTheBubbleWanted, .theSummaryAndTheKeptRecordingFollowThePresses)
- 355: (suite: GIFMakerTests.noReservedColoursLeavesTheRingColoursOut, GIFPaletteBuilderTests.noReservedColoursIsR2sPalette)
- 361: (suite, in part: CameraChoiceTests.aMissingDeviceTakesThePreferredCameraAndSaysSo, .aMissingDeviceWithNoCameraTakesNoneAndNamesIt, .systemDefaultWithNoCameraTakesNone, .theStrings; the note posting after Stop through `saveRecording` is not driven and stays by hand)
- 363: (suite, in part: CameraChoiceTests.accessNotAuthorizedTakesNoCameraAndGivesTheAccessNote, CameraNoteTests.theStartsNoteWhenWanted; the note posting after Stop through `saveRecording` is not driven and stays by hand)
- 369: (suite: CameraNoteTests.noNoteWhenTheBubbleWasNeverWanted, RecordingControllerTests.theSummaryAndTheKeptRecordingFollowThePresses)
- 409: (suite: CameraChoiceTests.aWindowRecordingDropsTheCameraAndItsNote, .anAreaOrFullscreenRecordingKeepsTheCameraAndItsNote)
- 414: (suite: RecordingControllerTests.aBubblePressBeforeTheFirstFrameAppliesAtOnceAndAHighlightsPressAtIt, .theTogglesFlipAndReachTheChrome)
- 415: (suite, in part: RecordingControllerTests.theSummaryAndTheKeptRecordingFollowThePresses, .theSummaryResetsAtTheNextRun, .highlightsMissedAfterTheFirstFrameAreNotUsed; `record()` reading the summary before `recorder.close()` is not driven)
- 417: (suite: CoordinatorRecordingTests.aSettingsPromptAsksOnlyWhenNothingElseRuns, .anOpenPromptRefusesCapturesUntilItIsAnswered, ShortcutsTests.aSettingsPromptWaitsWhileACaptureRecordingOrPromptRuns, .aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen)
- 420: (suite: ClickHighlighterTests.aLocalEventPasses)
- 421: (suite: ClickHighlightRuleTests.aSecondDownOfAHeldButtonEndsTheOldRingFirst, .aSecondDownOutsideEndsTheOldRingOnly)
- 424: (suite: RecordingExtrasPlaceTests.anAreaOnThePrimaryDisplay, .fullscreenUsesTheVisibleFrameAndHasNoRingArea, .anAreaOnASecondDisplayLeftOfAndBelowThePrimary, .fullscreenOnASecondDisplay, .anAreaAcrossTheDisplaysEdgeIsCutToIt, .anAreaOffTheDisplayPutsTheBubbleInTheVisibleFrame)
- 427: (suite: CameraSessionTests.takes720pAt30OverLargerAndSmallerFormats, .skipsA720pThatReachesOnly15fps, .nothingWhenNoFormatReaches30, .theSmallerOfTwoAtTheSameDistance)
- 428: (suite: ClickHighlightRuleTests.theColoursComponentsAndGIFColours, GIFMakerTests.reservedRingColoursLeadTheGlobalTable)
- 441: (suite: WebcamBubblePanelTests.aLossShowsTheSymbolOnGrey, .aLossWhileHiddenShowsOnlyOnceThePictureIsBack)
- 455: (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)

## recording-r4

Lines 308-360 and 370-376 are confirm-or-overrule calls: the mark goes before the blank, which stays Tim's. Eighteen
D lines already carry a mark; each was checked against its test, and the bullet says "already marked" with "keep" or
the replacement.

- 175: (suite: URLCommandHandlerTests.recordScreenRefusesARectUnder32Points)
- 201: (suite: URLCommandGateTests.theRecordingCommandsNeedOnlyURLCommandsOn, .withURLCommandsOffEveryCommandIsRefused, URLCommandHandlerTests.withURLCommandsOffEveryURLIsRefusedAlike)
- 228: (suite: UploadQueueTests.aFileOneByteUnderTheThresholdUsesTheSinglePUT, MultipartPlanTests.usesAtTheThresholdForAFile, .standardPlanAndLimits)
- 238: already marked; replace with (suite: CoordinatorDeleteTests.anAbortThatAnswers204IsSentAgain, .anAbortFailureAsksToRemoveFromHistory, CaptureDeletionTests.confirmationCountsTheMultipartObject, .abortsListTheStoredUploadOrNone). The present mark names the bare suite `CaptureDeletionTests`, and the 204 test calls `abortUploads` directly, so it needs the failure test to show Delete reaching the abort.
- 240: already marked; replace with (suite, in part: CoordinatorDeleteTests.anAbortFailureAsksToRemoveFromHistory, CaptureDeletionTests.alertTexts; the real IAM 403's text, the alert itself and the sidecar's removal on Remove stay by hand)
- 243: already marked (suite, in part: CoordinatorUploadTests.aStoredUploadAtAnotherLocationIsAbortedThereAndStartsAgain); keep. What stays: the old real bucket listing no incomplete upload.
- 245: already marked (suite: CoordinatorUploadTests.aSourceWhoseSizeChangedStartsAgainAbortingFirst); keep, or add MultipartPlanTests.startsOverWhenTheSourceDateDiffers for the same-size Save As case.
- 247: already marked (suite: UploadQueueTests.aSinglePutJobWithAnUploadToAbortAbortsItFirst); keep.
- 258: already marked (suite: CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination); keep.
- 265: (suite, in part: MultipartPlanTests.fitsUpTo625GiB, .partSizeIsNilAbove625GiB, RecordingSavePlanTests.oversizedNotice, .oversizedSaveFolderFileStays, .oversizedPendingFileMovesIntoTheSaveFolder; the coordinator's `refuseOversizedUpload` has no test, and the line already says nothing to run)
- 278: already marked (suite: CoordinatorDragOutTests.aCloseDuringTheTransferDropsWhatLands); keep.
- 280: already marked (suite: CoordinatorDragOutTests.deleteCancelsARunningDownloadAndRemovesTheFolder); keep.
- 281: already marked (suite, in part: RecentCaptureFormattingTests.detailSaysDownloadingWhileADragDownloadRuns); keep. What stays: the menu row as drawn.
- 286: already marked (suite: DragDownloadRuleTests.startsForNothingElse); keep.
- 287: already marked (suite: CoordinatorDragOutTests.tooLittleFreeSpaceRefusesTheDownload); keep.
- 289: already marked (suite, in part: DragDownloadRuleTests.startsForAnUploadedVideoOrGIFWithNoLocalFile); keep. What stays: a GIF's download landing, which no coordinator test runs.
- 302: (suite: QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)
- 308: (suite: URLCommandTests.theRecordingCommandsParseFromTheHostAndThePath, .recordScreenTakesTheActionTheRectAndTheDisplay, .scrollingCaptureIsCleanShotsNameForCaptureScrolling)
- 309: (suite: URLCommandTests.recordScreenRefusesTheActionsARecordingCannotDo, .theActionsEachKindTakes)
- 310: (suite: URLCommandHandlerTests.recordScreenRefusesARectUnder32Points)
- 312: (suite: URLCommandHandlerTests.aBurstStartsThenStopsAndDropsALaterCapture)
- 314: (suite: ShortcutsTests.aRefusedCaptureNamesTheRecordingThenTheLockThenThePrompt, URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped, .captureCommandsAreDroppedWhileCapturesAreRefused)
- 315: (suite, in part: ShortcutsTests.aURLStartRunsOnlyIdleOrSavingWithNoPromptAndNoQuit, .aRefusedCaptureNamesTheRecordingThenTheLockThenThePrompt; the coordinator starting a recording from `.saving` has no test)
- 316: (suite: CoordinatorRecordingTests.stopRecordingDuringACountInCancelsIt, .theStartCancelResetsOnlyWhenACountInBegins, .recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled)
- 317: (suite: CoordinatorRecordingTests.stopRecordingWhileIdleOrSavingChangesNothing)
- 318: (suite: MultipartPlanTests.usesAtTheThresholdForAFile, .neverUsesForData, .standardPlanAndLimits, UploadQueueTests.aFileAtTheThresholdGoesMultipart)
- 319: (suite: MultipartPlanTests.partSizeIsTheBaseUpTo10000Parts, .partSizeIsRaisedToAWholeMiBAbove10000Parts, .partSizeIsNilAbove625GiB, .fitsUpTo625GiB)
- 320: (suite: UploadQueueTests.partsAreSentThreeAtATimeInPartOrder, MultipartPlanTests.standardPlanAndLimits)
- 321: (suite, in part: UploadQueueTests.readPartReadsItsRange, MultipartRequestsTests.everyPayloadHashIsTheBodysHash; the send through `upload(for:from:)` is a code read)
- 322: (suite: UploadQueueTests.aFailingPartRetriesAloneWhileTheOthersFinish, .aPartOutOfTriesFailsTheJob, .createRetriesUnderThePolicy, .completeRetriesUnderThePolicy, .listPartsRetriesUnderThePolicy, .anUploadIDGoneOnEveryCreateFailsAfterTwoRestarts, MultipartPlanTests.standardPlanAndLimits)
- 325: (suite: QuickAccessModelTests.uploadingShowsTheFraction, RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState, UploadQueueTests.theFractionCountsInFlightBytesAndEndsAtOne)
- 327: (suite, in part: MultipartStoreTests.sweepRemovalsDropsNoStateAndStatesOlderThanSevenDays, .sweepRemovalsKeepsAStateExactlySevenDaysOldAndListsOnlyFileIDs, .sweepLeavesOnlyTheFilesOfAStateYoungerThanSevenDays; `start()` running the sweep at launch is not driven)
- 328: (suite: CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination)
- 331: (suite, in part: DragDownloadRuleTests.startsForAnUploadedVideoOrGIFWithNoLocalFile; a GIF's download landing has no coordinator test, as on line 289)
- 332: (suite: DragDownloadTests.aChunkedBodyReportsRisingFractionsAndLands, CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload)
- 333: (suite: RecentCaptureFormattingTests.detailSaysDownloadingWhileADragDownloadRuns)
- 334: (suite, in part: CoordinatorDragOutTests.aCloseDuringTheTransferDropsWhatLands, .aFailureAfterACancelKeepsNothing; that the card has no Cancel control is a view read)
- 335: (suite: QuickAccessModelTests.aFailedDragDownloadShowsTheErrorAndLeavesTheUpload, CoordinatorDragOutTests.aDragWithinTheWindowResumesFromTheKeptData)
- 336: (suite: DragDownloadRuleTests.usesResumeDataForUnderFourteenMinutes, CoordinatorDragOutTests.aDragWithinTheWindowResumesFromTheKeptData, .aDragPastTheWindowStartsAgainAndRemovesThePartialFile)
- 337: (suite: DragDownloadRuleTests.hasRoomForTheFileAndOneGB, CoordinatorDragOutTests.tooLittleFreeSpaceRefusesTheDownload)
- 345: (suite, in part: UploadQueueTests.aFileAtTheThresholdGoesMultipart; that the queue holds no location of its own is a code read)
- 346: (suite, in part: UploadQueueTests.aFailingPartRetriesAloneWhileTheOthersFinish, .aMultipartJobsAbortThatFindsNothingIsLoggedAsGone; the coordinator passing `environment.log` is a code read). The catalogue named `makeMultipartQueue` (a helper, not a test) and `aPartOutOfTriesFailsTheJob`, which asserts no log line; the two named here read the injected log.
- 349: (suite: CoordinatorRecordingTests.theStartCancelResetsOnlyWhenACountInBegins)
- 350: (suite: DragDownloadTests.theFileIsAtTheLandingPathWhenTheCallReturns, .aCompletionBeforeStartIsKeptForStart, .aTaskCancelledBeforeStartStillResumes, .resumeDataContinuesWithARangeRequest)
- 351: (suite: MultipartStoreTests.theFolderIsMultipartNextToTheHistoryAndFilesAreNamedByID)
- 354: (suite: SelectionOutcomeTests.recordingModeClickInThePresetRecordsIt, .otherModesIgnoreThePresetClick)
- 358: (suite, in part: S3DestinationTests.errorBodyIsSummarisedFromS3XML, .errorBodyIsTruncatedWhenNotXML; the members' access level is a code read)
- 359: (suite: S3DestinationTests.abortGives204Then404, CoordinatorDeleteTests.anAbortThatFindsNothingIsNotRepeatedAndLogsItGone)
- 360: (suite: DragFileStoreTests.landingURLIsAFreshPathInTheDownloadsFolder)
- 370: already marked (suite: UploadQueueTests.aSidecarUnwritableAtCreateFailsTheJob, .aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete, .aNewUploadWhoseFirstSidecarCannotBeWrittenIsAborted); keep.
- 372: already marked (suite: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource); keep.
- 373: already marked (suite: UploadQueueTests.aSinglePutJobWithAnUploadToAbortAbortsItFirst); keep.
- 374: already marked (suite: UploadQueueTests.aSecondRejectedPartListRestarts); keep.
- 375: already marked (suite: CoordinatorUploadTests.aResumesStartSetsTheBarAtItsDoneFraction, UploadQueueTests.aResumeSendsOnlyTheMissingParts); keep.
- 376: already marked (suite: UploadQueueTests.aJobWithAnUploadToAbortAbortsItBeforeItsCreate, .aSinglePutJobAbortsOnceAcrossItsRetries, .aSecondRejectedPartListRestarts); keep.

## small-tweaks

- 10: (suite: AppSettingsTests.confirmBeforeDeletingDefaultsToTrueAndPersists) The line is a put-back step, not a check; the mark only says the toggle persists either way. Leaving it unmarked is just as right.

## Not covered after all

No test pins the rule on any of these five lines. Each is a confirm-or-overrule call with no runtime rule, so the
closest category is C: Tim settles it by reading the code. No D line named a test that turned out to be missing. Two
looked missing at first, `RecordingConfigurationTests.outputSizeCapsTheLongerSideAt4096` and
`ClickHighlighterTests.aLocalEventPasses`, but both exist as parameterized tests. One named a helper instead of a
test (recording-r4 346, corrected in its bullet).

- coordinator-harness 49 (call 6, the fifty-six tests as this phase's set): C. No test pins it; it is a scope call, and the evidence is a count of `@Test` functions. It stays Tim's to confirm by reading the suites.
- coordinator-harness 53 (call 9, the three-file queue split with 24 widenings): C. No named test; the evidence is file sizes and "UploadQueueTests exercises the moved bodies", which pins the queue's behaviour, not the split. The structure is a code read for Tim.
- recording-r1 329 (gap 2, the extra parameters on `saveRecording` and `optimisedVideo`): C. No test pins it; the evidence is that the signatures compile and a test helper calls one. It is a confirm-or-overrule call with no runtime rule, so it stays Tim's by reading the code.
- recording-r2 635 (item 12, `saveRecording`'s new defaulted parameters): C. The catalogue names no test; the defaults are compile-enforced in the signature. A confirm-or-overrule call with nothing to run, so it stays Tim's by reading the code.
- recording-r4 344 (internal 2, `MultipartRequests` builds no path): C. No named test; the shape is compile-enforced, and "MultipartRequestsTests build every call without one" is not a test of the rule. It stays Tim's by reading `MultipartRequests.swift`.
