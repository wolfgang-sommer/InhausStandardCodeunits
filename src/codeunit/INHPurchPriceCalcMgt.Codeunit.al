codeunit 50129 INHPurchPriceCalcMgt
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // HO°           SSC  05.11.10  Gibt Kreditoren bei denen um Netto EP eingekauft wird
    // Axx°          RBI  11.08.08  Einkaufsverwaltung
    // Axx°.1        SSC  30.09.24  Preis in Bestellung umrechnen wenn Währung abweicht zwischen Beleg und Preiszeile
    // A94°          RBI  11.02.10  Preisfindung ändern auf Artikelgruppe EK in Purchase Price für Grundrabatt
    //               RBI  13.09.10  Preisfindung um Mengenstaffel erweitern. Bisher wurde immer der letzte, den Filtern entsprechende,
    //                              Einkaufspreis gezogen. Jetzt wird von allen gefundenen der Einkaufspreis mit der passenden
    //                              Mengenstaffel genommen.
    // A94°.1        SSC  10.12.15  Bei Div keinen Durchschnittspreis suchen
    // A94°.2        SSC  05.04.19  Beim Bestellvorschlag nicht mit altem Datum rechnen
    // C01°          SSC  04.11.15  Preiskalkulation
    //               SSC  08.07.16  Auch andere Währungen berücksichtigen bei Preisfindung
    //               SSC  01.04.25  Kalkulationskurs verwenden (Option bei fnk_ExchCurr von 1 auf 2 stellen)
    // C27°          SSC  17.04.18  Hooks
    // 
    // TODO:
    //  - Anpassung der Parameter von alter FNK_IsInMinQty nötig?


    trigger OnRun()
    begin
    end;

    var
        GLSetup: Record "General Ledger Setup";
        Item: Record Item;
        SKU: Record "Stockkeeping Unit";
        Vend: Record Vendor;
        ResCost: Record "Resource Cost";
        Currency: Record Currency;
        TempPurchPrice: Record "Purchase Price" temporary;
        TempPurchLineDisc: Record "Purchase Line Discount" temporary;
        LineDiscPerCent: Decimal;
        Qty: Decimal;
        QtyPerUOM: Decimal;
        VATPerCent: Decimal;
        PricesInclVAT: Boolean;
        VATBusPostingGr: Code[20];
        PricesInCurrency: Boolean;
        PriceInSKU: Boolean;
        CurrencyFactor: Decimal;
        ExchRateDate: Date;
        FoundPurchPrice: Boolean;
        DateCaption: Text[30];
        Text000: Label '%1 is less than %2 in the %3.';
        Text001: Label 'The %1 in the %2 must be same as in the %3.';
        "+++VAR_INHAUS+++": Boolean;
        IC_Beleg: Boolean;
        bo_TempPurch: Boolean;
        op_ExchRateType: Option " ",Budgetkurs,Kalkulationskurs;

    procedure FindPurchLinePrice(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; CalledByFieldNo: Integer)
    begin
        fnk_CheckIfIC(PurchHeader."Buy-from Vendor No.");   //Axx°
        with PurchLine do begin
            SetCurrency(
              PurchHeader."Currency Code", PurchHeader."Currency Factor", PurchHeaderExchDate(PurchHeader));
            SetVAT(PurchHeader."Prices Including VAT", "VAT %", "VAT Bus. Posting Group");
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            SetLineDisc("Line Discount %");

            TestField("Qty. per Unit of Measure");
            if PricesInCurrency then
                PurchHeader.TestField("Currency Factor");

            case Type of
                Type::Item:
                    begin
                        Item.Get("No.");
                        Vend.Get("Pay-to Vendor No.");
                        PriceInSKU := SKU.Get("Location Code", "No.", "Variant Code");
                        PurchLinePriceExists(PurchHeader, PurchLine, false);
                        CalcBestDirectUnitCost(TempPurchPrice);
                        if (FoundPurchPrice or
                            not ((CalledByFieldNo = FieldNo(Quantity)) or
                                 ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))) and
                           ("Prepmt. Amt. Inv." = 0)
                        then
                            "Direct Unit Cost" := TempPurchPrice."Direct Unit Cost";
                    end;
            end;
            OnAfterFindPurchLinePrice(PurchLine, PurchHeader, TempPurchPrice, CalledByFieldNo);
        end;

        fnk_OnAfterFindPurchLinePrice(PurchLine, PurchHeader, TempPurchPrice, CalledByFieldNo);   //C27°
    end;

    procedure FindItemJnlLinePrice(var ItemJnlLine: Record "Item Journal Line"; CalledByFieldNo: Integer)
    begin
        with ItemJnlLine do begin
            TestField("Qty. per Unit of Measure");
            SetCurrency('', 0, 0D);
            SetVAT(false, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            Item.Get("Item No.");
            PriceInSKU := SKU.Get("Location Code", "Item No.", "Variant Code");

            FindPurchPrice(
              TempPurchPrice, '', "Item No.", "Variant Code",
              "Unit of Measure Code", '', "Posting Date", false);

            OnFindItemJnlLinePriceOnBeforeCalcBestDirectUnitCost(ItemJnlLine, TempPurchPrice);
            CalcBestDirectUnitCost(TempPurchPrice);

            if FoundPurchPrice or
               not ((CalledByFieldNo = FieldNo(Quantity)) or
                    ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))
            then
                "Unit Amount" := TempPurchPrice."Direct Unit Cost";
        end;
    end;

    procedure FindReqLinePrice(var ReqLine: Record "Requisition Line"; CalledByFieldNo: Integer)
    var
        VendorNo: Code[20];
        IsHandled: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        xReqLine: Record "Requisition Line";
    begin
        with ReqLine do
            if Type = Type::Item then begin
                if not Vend.Get("Vendor No.") then
                    Vend.Init
                else
                    if Vend."Pay-to Vendor No." <> '' then
                        if not Vend.Get(Vend."Pay-to Vendor No.") then
                            Vend.Init;
                if Vend."No." <> '' then
                    VendorNo := Vend."No."
                else
                    VendorNo := "Vendor No.";

                fnk_CheckIfIC(VendorNo);   //Axx°
                                           //START A94°.2 ---------------------------------
                xReqLine := ReqLine;
                if "Order Date" < WorkDate then begin
                    "Order Date" := WorkDate;
                end;
                //STOP  A94°.2 ---------------------------------

                SetCurrency("Currency Code", "Currency Factor", "Order Date");
                SetVAT(Vend."Prices Including VAT", 0, '');
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

                TestField("Qty. per Unit of Measure");
                if PricesInCurrency then
                    TestField("Currency Factor");

                Item.Get("No.");
                PriceInSKU := SKU.Get("Location Code", "No.", "Variant Code");

                IsHandled := false;
                OnBeforeFindReqLinePrice(TempPurchPrice, ReqLine, IsHandled);
                if not IsHandled then
                    FindPurchPrice(
                      TempPurchPrice, VendorNo, "No.", "Variant Code",
                      "Unit of Measure Code", "Currency Code", "Order Date", false);
                CalcBestDirectUnitCost(TempPurchPrice);

                if FoundPurchPrice or
                   not ((CalledByFieldNo = FieldNo(Quantity)) or
                        ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))
                then
                    "Direct Unit Cost" := TempPurchPrice."Direct Unit Cost";

                "Order Date" := xReqLine."Order Date";   //A94°.2
            end;

        OnAfterFindReqLinePrice(ReqLine, TempPurchPrice, CalledByFieldNo);
    end;

    procedure FindPurchLineLineDisc(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line")
    begin
        with PurchLine do begin
            SetCurrency(PurchHeader."Currency Code", 0, 0D);
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            if Type = Type::Item then begin
                PurchLineLineDiscExists(PurchHeader, PurchLine, false);
                CalcBestLineDisc(TempPurchLineDisc);

                "Line Discount %" := TempPurchLineDisc."Line Discount %";
            end;

            OnAfterFindPurchLineLineDisc(PurchLine, PurchHeader, TempPurchLineDisc);
        end;

        fnk_OnAfterFindPurchLineLineDisc(PurchLine, PurchHeader, TempPurchLineDisc);   //C27°
    end;

    procedure FindStdItemJnlLinePrice(var StdItemJnlLine: Record "Standard Item Journal Line"; CalledByFieldNo: Integer)
    begin
        with StdItemJnlLine do begin
            TestField("Qty. per Unit of Measure");
            SetCurrency('', 0, 0D);
            SetVAT(false, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            Item.Get("Item No.");
            PriceInSKU := SKU.Get("Location Code", "Item No.", "Variant Code");

            FindPurchPrice(
              TempPurchPrice, '', "Item No.", "Variant Code",
              "Unit of Measure Code", '', WorkDate, false);
            CalcBestDirectUnitCost(TempPurchPrice);

            if FoundPurchPrice or
               not ((CalledByFieldNo = FieldNo(Quantity)) or
                    ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))
            then
                "Unit Amount" := TempPurchPrice."Direct Unit Cost";
        end;
    end;

    procedure FindReqLineDisc(var ReqLine: Record "Requisition Line")
    var
        IsHandled: Boolean;
    begin
        with ReqLine do begin
            SetCurrency("Currency Code", 0, 0D);
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            if Type = Type::Item then begin
                IsHandled := false;
                OnBeforeFindReqLineDisc(ReqLine, TempPurchLineDisc, IsHandled);
                if not IsHandled then
                    FindPurchLineDisc(
                      TempPurchLineDisc, "Vendor No.", "No.", "Variant Code",
                      "Unit of Measure Code", "Currency Code", "Order Date", false,
                      "Qty. per Unit of Measure", Abs(Quantity));
                OnAfterFindReqLineDisc(ReqLine);
                CalcBestLineDisc(TempPurchLineDisc);

                "Line Discount %" := TempPurchLineDisc."Line Discount %";
            end;
        end;

        fnk_OnAfterFindReqLineDisc(ReqLine);   //C27°
        //TODO: Da das eine EventSub Funktion ist, quasi doppelt gemoppelt, aber "Line Discount %" wird darin bearbeitet und das passiert hier nach dem Event
        //  prüfen, umbauen, auslagern
    end;

    local procedure CalcBestDirectUnitCost(var PurchPrice: Record "Purchase Price")
    var
        BestPurchPrice: Record "Purchase Price";
        IsHandled: Boolean;
        BestPurchPriceFound: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_GeneralMgtIH: Codeunit "GeneralMgt IH";
        lo_cu_ItemMgt: Codeunit INHItemMgt;
        lo_co_ToCurr: Code[10];
    begin
        lo_co_ToCurr := PurchPrice."Currency Code";   //C01°
        with PurchPrice do begin
            FoundPurchPrice := Find('-');
            if FoundPurchPrice then
                repeat
                    if IsInMinQty("Unit of Measure Code", "Minimum Quantity") then begin
                        ConvertPriceToVAT(
                          Vend."Prices Including VAT", Item."VAT Prod. Posting Group",
                          Vend."VAT Bus. Posting Group", "Direct Unit Cost");
                        ConvertPriceToUoM("Unit of Measure Code", "Direct Unit Cost");
                        //START C01° ---------------------------------
                        //        ConvertPriceLCYToFCY("Currency Code","Direct Unit Cost");
                        "Direct Unit Cost" := lo_cu_GeneralMgtIH.fnk_ExchCurr(WorkDate, "Currency Code", lo_co_ToCurr, "Direct Unit Cost", op_ExchRateType);
                        //STOP  C01° ---------------------------------

                        case true of
                            ((BestPurchPrice."Currency Code" = '') and ("Currency Code" <> '')) or
                            ((BestPurchPrice."Variant Code" = '') and ("Variant Code" <> '')):
                                begin
                                    BestPurchPrice := PurchPrice;
                                    BestPurchPriceFound := true;
                                end;
                            ((BestPurchPrice."Currency Code" = '') or ("Currency Code" <> '')) and
                          ((BestPurchPrice."Variant Code" = '') or ("Variant Code" <> '')):
                                if (BestPurchPrice."Direct Unit Cost" = 0) or
                                   //START A94° ----------------------------------------------
                                   //Bestpreisfindung ausklammern, stattdessen die passende Mengenstaffel verwenden
                                   //               (CalcLineAmount(BestPurchPrice) > CalcLineAmount(PurchPrice))
                                   (BestPurchPrice."Minimum Quantity" <= PurchPrice."Minimum Quantity")
                                //STOP A94° ----------------------------------------------
                                then begin
                                    BestPurchPrice := PurchPrice;
                                    BestPurchPriceFound := true;
                                end;
                        end;
                    end;
                until Next = 0;
        end;

        // No price found in agreement
        //START Axx° ---------------------------------
        if IC_Beleg and (not BestPurchPriceFound)
          and not Item.fnk_IsDIV   //A94°.1
        then begin
            //STOP  Axx° ---------------------------------
            IsHandled := false;
            OnCalcBestDirectUnitCostOnBeforeNoPriceFound(BestPurchPrice, Item, IsHandled);
            if not IsHandled then begin
                PriceInSKU := PriceInSKU and (SKU."Last Direct Cost" <> 0);
                if PriceInSKU then
                    BestPurchPrice."Direct Unit Cost" := SKU."Last Direct Cost"
                else
                    BestPurchPrice."Direct Unit Cost" := Item."Last Direct Cost";
            end;
            //START C24° ---------------------------------
            if BestPurchPrice."Direct Unit Cost" = 0 then begin
                BestPurchPrice."Direct Unit Cost" := lo_cu_ItemMgt.FNK_NettoEPZuArtikel(Item."No.", WorkDate, Item."Vendor No.", Item."Base Unit of Measure");
            end;
            //STOP  C24° ---------------------------------
            ConvertPriceToVAT(false, Item."VAT Prod. Posting Group", '', BestPurchPrice."Direct Unit Cost");
            ConvertPriceToUoM('', BestPurchPrice."Direct Unit Cost");
            ConvertPriceLCYToFCY('', BestPurchPrice."Direct Unit Cost");
            OnCalcBestDirectUnitCostOnAfterSetUnitCost(BestPurchPrice);
        end;

        PurchPrice := BestPurchPrice;
    end;

    local procedure CalcBestLineDisc(var PurchLineDisc: Record "Purchase Line Discount")
    var
        BestPurchLineDisc: Record "Purchase Line Discount";
    begin
        with PurchLineDisc do
            if Find('-') then
                repeat
                    if IsInMinQty("Unit of Measure Code", "Minimum Quantity") then
                        case true of
                            ((BestPurchLineDisc."Currency Code" = '') and ("Currency Code" <> '')) or
                          ((BestPurchLineDisc."Variant Code" = '') and ("Variant Code" <> '')):
                                BestPurchLineDisc := PurchLineDisc;
                            ((BestPurchLineDisc."Currency Code" = '') or ("Currency Code" <> '')) and
                          ((BestPurchLineDisc."Variant Code" = '') or ("Variant Code" <> '')):
                                if BestPurchLineDisc."Line Discount %" < "Line Discount %" then
                                    BestPurchLineDisc := PurchLineDisc;
                        end;
                until Next = 0;

        PurchLineDisc := BestPurchLineDisc;
    end;

    local procedure FindPurchPrice(var ToPurchPrice: Record "Purchase Price"; VendorNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    var
        FromPurchPrice: Record "Purchase Price";
    begin
        OnBeforeFindPurchPrice(
          ToPurchPrice, FromPurchPrice, VendorNo, ItemNo, VariantCode, UOM, CurrencyCode, StartingDate, ShowAll, Qty, QtyPerUOM);

        with FromPurchPrice do begin
            SetRange("Item No.", ItemNo);
            SetRange("Vendor No.", VendorNo);
            SetFilter("Ending Date", '%1|>=%2', 0D, StartingDate);
            SetFilter("Variant Code", '%1|%2', VariantCode, '');
            if not ShowAll then begin
                SetRange("Starting Date", 0D, StartingDate);
                SetFilter("Currency Code", '%1|%2', CurrencyCode, '');
                SetFilter("Unit of Measure Code", '%1|%2', UOM, '');
            end;
            //START C01° ---------------------------------
            if Count = 0 then begin
                SetRange("Currency Code");
            end;
            //STOP  C01° ---------------------------------

            ToPurchPrice.Reset;
            ToPurchPrice.DeleteAll;
            if Find('-') then
                repeat
                    ToPurchPrice := FromPurchPrice;
                    ToPurchPrice.Insert;
                until Next = 0;
        end;

        OnAfterFindPurchPrice(
          ToPurchPrice, FromPurchPrice, VendorNo, ItemNo, VariantCode, UOM, CurrencyCode, StartingDate, ShowAll, Qty, QtyPerUOM);
    end;

    local procedure FindPurchLineDisc(var ToPurchLineDisc: Record "Purchase Line Discount"; VendorNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean; QuantityPerUoM: Decimal; Quantity: Decimal)
    var
        FromPurchLineDisc: Record "Purchase Line Discount";
    begin
        with FromPurchLineDisc do begin
            SetRange("Item No.", ItemNo);
            SetRange("Vendor No.", VendorNo);
            SetFilter("Ending Date", '%1|>=%2', 0D, StartingDate);
            SetFilter("Variant Code", '%1|%2', VariantCode, '');
            if not ShowAll then begin
                SetRange("Starting Date", 0D, StartingDate);
                SetFilter("Currency Code", '%1|%2', CurrencyCode, '');
                SetFilter("Unit of Measure Code", '%1|%2', UOM, '');
            end;

            ToPurchLineDisc.Reset;
            ToPurchLineDisc.DeleteAll;

            if Find('-') then
                repeat
                    ToPurchLineDisc := FromPurchLineDisc;
                    ToPurchLineDisc.Insert;
                until Next = 0;
        end;

        OnAfterFindPurchLineDisc(ToPurchLineDisc, FromPurchLineDisc, ItemNo, QuantityPerUoM, Quantity, ShowAll);
    end;

    local procedure SetCurrency(CurrencyCode2: Code[10]; CurrencyFactor2: Decimal; ExchRateDate2: Date)
    begin
        PricesInCurrency := CurrencyCode2 <> '';
        if PricesInCurrency then begin
            Currency.Get(CurrencyCode2);
            Currency.TestField("Unit-Amount Rounding Precision");
            CurrencyFactor := CurrencyFactor2;
            ExchRateDate := ExchRateDate2;
        end else
            GLSetup.Get;
    end;

    local procedure SetVAT(PriceInclVAT2: Boolean; VATPerCent2: Decimal; VATBusPostingGr2: Code[20])
    begin
        PricesInclVAT := PriceInclVAT2;
        VATPerCent := VATPerCent2;
        VATBusPostingGr := VATBusPostingGr2;
    end;

    local procedure SetUoM(Qty2: Decimal; QtyPerUoM2: Decimal)
    begin
        Qty := Qty2;
        QtyPerUOM := QtyPerUoM2;
    end;

    local procedure SetLineDisc(LineDiscPerCent2: Decimal)
    begin
        LineDiscPerCent := LineDiscPerCent2;
    end;

    local procedure IsInMinQty(UnitofMeasureCode: Code[10]; MinQty: Decimal): Boolean
    begin
        if UnitofMeasureCode = '' then
            exit(MinQty <= QtyPerUOM * Qty);
        exit(MinQty <= Qty);
    end;

    local procedure ConvertPriceToVAT(FromPriceInclVAT: Boolean; FromVATProdPostingGr: Code[20]; FromVATBusPostingGr: Code[20]; var UnitPrice: Decimal)
    var
        VATPostingSetup: Record "VAT Posting Setup";
    begin
        if FromPriceInclVAT then begin
            if not VATPostingSetup.Get(FromVATBusPostingGr, FromVATProdPostingGr) then
                VATPostingSetup.Init;
            OnBeforeConvertPriceToVAT(VATPostingSetup);

            if PricesInclVAT then begin
                if VATBusPostingGr <> FromVATBusPostingGr then
                    UnitPrice := UnitPrice * (100 + VATPerCent) / (100 + VATPostingSetup."VAT %");
            end else
                UnitPrice := UnitPrice / (1 + VATPostingSetup."VAT %" / 100);
        end else
            if PricesInclVAT then
                UnitPrice := UnitPrice * (1 + VATPerCent / 100);
    end;

    local procedure ConvertPriceToUoM(UnitOfMeasureCode: Code[10]; var UnitPrice: Decimal)
    begin
        if UnitOfMeasureCode = '' then
            UnitPrice := UnitPrice * QtyPerUOM;
    end;

    local procedure ConvertPriceLCYToFCY(CurrencyCode: Code[10]; var UnitPrice: Decimal)
    var
        CurrExchRate: Record "Currency Exchange Rate";
    begin
        if PricesInCurrency then begin
            if CurrencyCode = '' then
                UnitPrice :=
                  CurrExchRate.ExchangeAmtLCYToFCY(ExchRateDate, Currency.Code, UnitPrice, CurrencyFactor);
            UnitPrice := Round(UnitPrice, Currency."Unit-Amount Rounding Precision");
        end else
            UnitPrice := Round(UnitPrice, GLSetup."Unit-Amount Rounding Precision");
    end;

    local procedure CalcLineAmount(PurchPrice: Record "Purchase Price"): Decimal
    begin
        with PurchPrice do
            exit("Direct Unit Cost" * (1 - LineDiscPerCent / 100));
    end;

    local procedure PurchLinePriceExists(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; ShowAll: Boolean): Boolean
    var
        IsHandled: Boolean;
    begin
        with PurchLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                IsHandled := false;
                OnBeforePurchLinePriceExists(PurchLine, PurchHeader, TempPurchPrice, ShowAll, IsHandled);
                if not IsHandled then
                    FindPurchPrice(
                      TempPurchPrice, "Pay-to Vendor No.", "No.", "Variant Code", "Unit of Measure Code",
                      PurchHeader."Currency Code", PurchHeaderStartDate(PurchHeader, DateCaption), ShowAll);
                OnAfterPurchLinePriceExists(PurchLine);
                exit(TempPurchPrice.Find('-'));
            end;
        exit(false);
    end;

    local procedure PurchLineLineDiscExists(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; ShowAll: Boolean): Boolean
    var
        IsHandled: Boolean;
    begin
        with PurchLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                IsHandled := false;
                OnBeforePurchLineLineDiscExists(PurchLine, PurchHeader, TempPurchLineDisc, ShowAll, IsHandled);
                if not IsHandled then
                    FindPurchLineDisc(
                      TempPurchLineDisc, "Pay-to Vendor No.", "No.", "Variant Code", "Unit of Measure Code",
                      PurchHeader."Currency Code", PurchHeaderStartDate(PurchHeader, DateCaption), ShowAll,
                      "Qty. per Unit of Measure", Quantity);
                OnAfterPurchLineLineDiscExists(PurchLine);
                exit(TempPurchLineDisc.Find('-'));
            end;
        exit(false);
    end;

    local procedure PurchHeaderExchDate(var PurchHeader: Record "Purchase Header"): Date
    begin
        with PurchHeader do begin
            if "Posting Date" <> 0D then
                exit("Posting Date");
            exit(WorkDate);
        end;
    end;

    local procedure PurchHeaderStartDate(var PurchHeader: Record "Purchase Header"; var DateCaption: Text[30]): Date
    begin
        with PurchHeader do
            if "Document Type" in ["Document Type"::Invoice, "Document Type"::"Credit Memo"] then begin
                DateCaption := FieldCaption("Posting Date");
                exit("Posting Date")
            end else begin
                DateCaption := FieldCaption("Order Date");
                exit("Order Date");
            end;
    end;

    procedure FindJobPlanningLinePrice(var JobPlanningLine: Record "Job Planning Line"; CalledByFieldNo: Integer)
    var
        JTHeader: Record Job;
    begin
        with JobPlanningLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Planning Date");
            SetVAT(false, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            case Type of
                Type::Item:
                    begin
                        Item.Get("No.");
                        PriceInSKU := SKU.Get('', "No.", "Variant Code");
                        JTHeader.Get("Job No.");

                        FindPurchPrice(
                          TempPurchPrice, '', "No.", "Variant Code", "Unit of Measure Code", '', "Planning Date", false);
                        PricesInCurrency := false;
                        GLSetup.Get;
                        CalcBestDirectUnitCost(TempPurchPrice);
                        SetCurrency("Currency Code", "Currency Factor", "Planning Date");

                        if FoundPurchPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))
                        then
                            "Direct Unit Cost (LCY)" := TempPurchPrice."Direct Unit Cost";
                    end;
                Type::Resource:
                    begin
                        ResCost.Init;
                        ResCost.Code := "No.";
                        ResCost."Work Type Code" := "Work Type Code";
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Cost", ResCost);
                        OnAfterJobPlanningLineFindResCost(JobPlanningLine, CalledByFieldNo, ResCost);
                        ConvertPriceLCYToFCY("Currency Code", ResCost."Unit Cost");
                        "Direct Unit Cost (LCY)" := Round(ResCost."Direct Unit Cost" * "Qty. per Unit of Measure",
                            Currency."Unit-Amount Rounding Precision");
                        Validate("Unit Cost (LCY)", Round(ResCost."Unit Cost" * "Qty. per Unit of Measure",
                            Currency."Unit-Amount Rounding Precision"));
                    end;
            end;
            Validate("Direct Unit Cost (LCY)");
        end;
    end;

    procedure FindJobJnlLinePrice(var JobJnlLine: Record "Job Journal Line"; CalledByFieldNo: Integer)
    var
        Job: Record Job;
        IsHandled: Boolean;
    begin
        with JobJnlLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Posting Date");
            SetVAT(false, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            case Type of
                Type::Item:
                    begin
                        Item.Get("No.");
                        PriceInSKU := SKU.Get('', "No.", "Variant Code");
                        Job.Get("Job No.");

                        FindPurchPrice(
                          TempPurchPrice, '', "No.", "Variant Code", "Unit of Measure Code", "Country/Region Code", "Posting Date", false);
                        PricesInCurrency := false;
                        GLSetup.Get;

                        OnFindJobJnlLinePriceOnBeforeCalcBestDirectUnitCost(JobJnlLine, TempPurchPrice);
                        CalcBestDirectUnitCost(TempPurchPrice);
                        SetCurrency("Currency Code", "Currency Factor", "Posting Date");

                        if FoundPurchPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                ((CalledByFieldNo = FieldNo("Variant Code")) and not PriceInSKU))
                        then
                            "Direct Unit Cost (LCY)" := TempPurchPrice."Direct Unit Cost";
                        OnAfterFindJobJnlLinePriceItem(JobJnlLine);
                    end;
                Type::Resource:
                    begin
                        ResCost.Init;
                        ResCost.Code := "No.";
                        ResCost."Work Type Code" := "Work Type Code";
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Cost", ResCost);
                        OnAfterJobJnlLineFindResCost(JobJnlLine, CalledByFieldNo, ResCost);
                        ConvertPriceLCYToFCY("Currency Code", ResCost."Unit Cost");
                        "Direct Unit Cost (LCY)" :=
                          Round(ResCost."Direct Unit Cost" * "Qty. per Unit of Measure", Currency."Unit-Amount Rounding Precision");
                        Validate("Unit Cost (LCY)",
                          Round(ResCost."Unit Cost" * "Qty. per Unit of Measure", Currency."Unit-Amount Rounding Precision"));
                        OnAfterFindJobJnlLinePriceResource(JobJnlLine);
                    end;
            end;
            OnAfterFindJobJnlLinePrice(JobJnlLine, IsHandled);
            if not IsHandled then
                Validate("Direct Unit Cost (LCY)");
        end;
    end;

    procedure NoOfPurchLinePrice(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; ShowAll: Boolean): Integer
    begin
        if PurchLinePriceExists(PurchHeader, PurchLine, ShowAll) then
            exit(TempPurchPrice.Count);
    end;

    procedure NoOfPurchLineLineDisc(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; ShowAll: Boolean): Integer
    begin
        if PurchLineLineDiscExists(PurchHeader, PurchLine, ShowAll) then
            exit(TempPurchLineDisc.Count);
    end;

    procedure GetPurchLinePrice(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line")
    begin
        PurchLinePriceExists(PurchHeader, PurchLine, true);

        with PurchLine do
            if PAGE.RunModal(PAGE::"Get Purchase Price", TempPurchPrice) = ACTION::LookupOK then begin
                SetVAT(PurchHeader."Prices Including VAT", "VAT %", "VAT Bus. Posting Group");
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
                SetCurrency(PurchHeader."Currency Code", PurchHeader."Currency Factor", PurchHeaderExchDate(PurchHeader));
                OnGetPurchLinePriceOnAfterLookup(PurchHeader, PurchLine, TempPurchPrice);

                if not IsInMinQty(TempPurchPrice."Unit of Measure Code", TempPurchPrice."Minimum Quantity") then
                    Error(
                      Text000,
                      FieldCaption(Quantity),
                      TempPurchPrice.FieldCaption("Minimum Quantity"),
                      TempPurchPrice.TableCaption);
                if not (TempPurchPrice."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempPurchPrice.TableCaption);
                if not (TempPurchPrice."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempPurchPrice.TableCaption);
                if TempPurchPrice."Starting Date" > PurchHeaderStartDate(PurchHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempPurchPrice.FieldCaption("Starting Date"),
                      TempPurchPrice.TableCaption);

                ConvertPriceToVAT(
                  PurchHeader."Prices Including VAT", Item."VAT Prod. Posting Group",
                  "VAT Bus. Posting Group", TempPurchPrice."Direct Unit Cost");
                ConvertPriceToUoM(TempPurchPrice."Unit of Measure Code", TempPurchPrice."Direct Unit Cost");
                ConvertPriceLCYToFCY(TempPurchPrice."Currency Code", TempPurchPrice."Direct Unit Cost");

                Validate("Direct Unit Cost", TempPurchPrice."Direct Unit Cost");
            end;

        OnAfterGetPurchLinePrice(PurchHeader, PurchLine, TempPurchPrice);
    end;

    procedure GetPurchLineLineDisc(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line")
    begin
        PurchLineLineDiscExists(PurchHeader, PurchLine, true);

        with PurchLine do
            if PAGE.RunModal(PAGE::"Get Purchase Line Disc.", TempPurchLineDisc) = ACTION::LookupOK then begin
                SetCurrency(PurchHeader."Currency Code", 0, 0D);
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
                OnGetPurchLineLineDiscOnAfterLookup(PurchHeader, PurchLine, TempPurchLineDisc);

                if not IsInMinQty(TempPurchLineDisc."Unit of Measure Code", TempPurchLineDisc."Minimum Quantity") then
                    Error(
                      Text000, FieldCaption(Quantity),
                      TempPurchLineDisc.FieldCaption("Minimum Quantity"),
                      TempPurchLineDisc.TableCaption);
                if not (TempPurchLineDisc."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempPurchLineDisc.TableCaption);
                if not (TempPurchLineDisc."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempPurchLineDisc.TableCaption);
                if TempPurchLineDisc."Starting Date" > PurchHeaderStartDate(PurchHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempPurchLineDisc.FieldCaption("Starting Date"),
                      TempPurchLineDisc.TableCaption);

                Validate("Line Discount %", TempPurchLineDisc."Line Discount %");
            end;
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobJnlLinePrice(var JobJournalLine: Record "Job Journal Line"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobJnlLinePriceItem(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobJnlLinePriceResource(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindPurchPrice(var ToPurchPrice: Record "Purchase Price"; FromPurchasePrice: Record "Purchase Price"; VendorNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean; Qty: Decimal; QtyPerUOM: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindPurchLinePrice(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var PurchasePrice: Record "Purchase Price"; CalledByFieldNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindPurchLineDisc(var ToPurchaseLineDiscount: Record "Purchase Line Discount"; var FromPurchaseLineDiscount: Record "Purchase Line Discount"; ItemNo: Code[20]; QuantityPerUoM: Decimal; Quantity: Decimal; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindPurchLineLineDisc(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var TempPurchLineDisc: Record "Purchase Line Discount" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindReqLinePrice(var ReqLine: Record "Requisition Line"; var TempPurchasePrice: Record "Purchase Price" temporary; CalledByFieldNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindReqLineDisc(var ReqLine: Record "Requisition Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetPurchLinePrice(var PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line"; var TempPurchasePrice: Record "Purchase Price" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobJnlLineFindResCost(var JobJournalLine: Record "Job Journal Line"; CalledByFieldNo: Integer; var ResourceCost: Record "Resource Cost")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobPlanningLineFindResCost(var JobPlanningLine: Record "Job Planning Line"; CalledByFieldNo: Integer; var ResourceCost: Record "Resource Cost")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPurchLineLineDiscExists(var PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPurchLinePriceExists(var PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConvertPriceToVAT(var VATPostingSetup: Record "VAT Posting Setup")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindPurchPrice(var ToPurchPrice: Record "Purchase Price"; var FromPurchasePrice: Record "Purchase Price"; var VendorNo: Code[20]; var ItemNo: Code[20]; var VariantCode: Code[10]; var UOM: Code[10]; var CurrencyCode: Code[10]; var StartingDate: Date; var ShowAll: Boolean; var Qty: Decimal; var QtyPerUOM: Decimal)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindReqLinePrice(var TempPurchasePrice: Record "Purchase Price" temporary; var ReqLine: Record "Requisition Line"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindReqLineDisc(var ReqLine: Record "Requisition Line"; var TempPurchaseLineDiscount: Record "Purchase Line Discount" temporary; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePurchLinePriceExists(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var TempPurchasePrice: Record "Purchase Price" temporary; ShowAll: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePurchLineLineDiscExists(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var TempPurchLineDisc: Record "Purchase Line Discount" temporary; ShowAll: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCalcBestDirectUnitCostOnAfterSetUnitCost(var PurchasePrice: Record "Purchase Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCalcBestDirectUnitCostOnBeforeNoPriceFound(var PurchasePrice: Record "Purchase Price"; Item: Record Item; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetPurchLinePriceOnAfterLookup(PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line"; var TempPurchasePrice: Record "Purchase Price" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetPurchLineLineDiscOnAfterLookup(PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line"; var TempPurchaseLineDiscount: Record "Purchase Line Discount" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFindItemJnlLinePriceOnBeforeCalcBestDirectUnitCost(var ItemJournalLine: Record "Item Journal Line"; var TempPurchasePrice: Record "Purchase Price" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFindJobJnlLinePriceOnBeforeCalcBestDirectUnitCost(var JobJournalLine: Record "Job Journal Line"; var TempPurchasePrice: Record "Purchase Price" temporary)
    begin
    end;

    local procedure "+++FNK_INHAUS+++"()
    begin
    end;

    local procedure fnk_CheckIfIC(par_co_Vend: Code[20])
    var
        lo_re_InitTable: Record "INHInitTable";
    begin
        //Axx°
        Clear(IC_Beleg);
        lo_re_InitTable.Get(CompanyName);
        if (lo_re_InitTable.IC_Vendor = par_co_Vend) then begin
            IC_Beleg := true;
        end else begin
            IC_Beleg := false;
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetPurchPriceAndDisc(var par_re_PurchLine: Record "Purchase Line"; par_op_ItemCostType: Option " ",Calc,Sales; var par_re_PurchPrice: Record "Purchase Price") rv_bo_Success: Boolean
    var
        lo_re_Item: Record Item;
        lo_re_PurchHdr: Record "Purchase Header" temporary;
        lo_re_PurchLine: Record "Purchase Line" temporary;
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
        lo_da_ToDate: Date;
    begin
        // *** Konditionen für einen Artikel; EK Preisfindung nachbilden   //C01°
        //     par_re_PurchLine verwenden um Optionen anzugeben
        //       "No."                    = Artikelnr.
        //       "Unit of Measure Code"   = Einheit
        //       Quantity                 = MindestMenge
        //       "Buy-from Vendor No."    = Kreditor
        //       "Expected Receipt Date"  = Zu Datum

        with lo_re_PurchLine do begin
            lo_re_Item.Get(par_re_PurchLine."No.");
            if par_re_PurchLine."Unit of Measure Code" = '' then par_re_PurchLine."Unit of Measure Code" := lo_re_Item."Base Unit of Measure";
            if par_re_PurchLine.Quantity = 0 then par_re_PurchLine.Quantity := 1;
            lo_da_ToDate := par_re_PurchLine."Expected Receipt Date";
            if lo_da_ToDate = 0D then lo_da_ToDate := WorkDate;
            if par_op_ItemCostType = par_op_ItemCostType::Sales then op_ExchRateType := op_ExchRateType::Kalkulationskurs;

            lo_re_PurchHdr."Document Type" := lo_re_PurchHdr."Document Type"::Order;
            lo_re_PurchHdr."No." := '66666';
            lo_re_PurchHdr.Validate("Order Date", lo_da_ToDate);
            lo_re_PurchHdr.Validate("Posting Date", lo_da_ToDate);
            lo_re_PurchHdr.Validate("Buy-from Vendor No.", par_re_PurchLine."Buy-from Vendor No.");

            "Document Type" := lo_re_PurchHdr."Document Type";
            "Document No." := lo_re_PurchHdr."No.";
            "Line No." := 1;
            "Buy-from Vendor No." := lo_re_PurchHdr."Buy-from Vendor No.";
            "Pay-to Vendor No." := lo_re_PurchHdr."Pay-to Vendor No.";
            "Currency Code" := lo_re_PurchHdr."Currency Code";
            Type := Type::Item;
            "No." := par_re_PurchLine."No.";
            "Unit of Measure Code" := par_re_PurchLine."Unit of Measure Code";
            Quantity := par_re_PurchLine.Quantity;

            lo_cu_PurchMgt.fnk_SetCalcToDate(lo_da_ToDate);
            fnk_IsTempPurch(true);
            FindPurchLinePrice(lo_re_PurchHdr, lo_re_PurchLine, 0);
            par_re_PurchPrice := TempPurchPrice;

            if par_op_ItemCostType = par_op_ItemCostType::" " then begin
                FindPurchLineLineDisc(lo_re_PurchHdr, lo_re_PurchLine);
            end else begin
                if par_re_PurchPrice."Item No." = '' then begin
                    lo_cu_PurchMgt.FNK_FindPurchPriceGrundrabatt("No.", "Buy-from Vendor No.", lo_da_ToDate, lo_da_ToDate, "Currency Code",
                                                                 "Variant Code", "Unit of Measure Code", 0, par_re_PurchPrice);
                end;
                //START HO° ---------------------------------
                if lo_cu_PurchMgt.fnk_VendHasNetUnitCost(lo_re_PurchHdr."Buy-from Vendor No.") then begin
                    //Keine Rabatte weil immer Netto EK als Preis
                end else begin
                    //STOP  HO° ---------------------------------
                    if par_re_PurchPrice."Net Price" then begin
                        "Summe Grundrabatte" := 0;
                    end else begin
                        "Summe Grundrabatte" :=
                          lo_cu_PurchMgt.FNK_KreditorGrundRabatt("Buy-from Vendor No.", "No.", par_re_PurchPrice."Artikelgruppe EK",
                                                                 par_op_ItemCostType, lo_da_ToDate);
                    end;
                    "Artikel Rabatt" := lo_cu_PurchMgt.fnk_GetPurchDiscount("No.", "Buy-from Vendor No.", par_op_ItemCostType);
                    "Line Discount %" := lo_cu_PurchMgt.FNK_RabattEKZeileBerechnen(lo_re_PurchLine);
                end;   //HO°
            end;

            par_re_PurchLine := lo_re_PurchLine;
            rv_bo_Success := true;
        end;
    end;

    [Scope('Internal')]
    procedure fnk_IsTempPurch(par_bo_TempPurch: Boolean)
    begin
        //C01°
        bo_TempPurch := par_bo_TempPurch;
    end;

    local procedure fnk_OnAfterFindPurchLinePrice(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var PurchasePrice: Record "Purchase Price"; CalledByFieldNo: Integer)
    var
        lo_cu_GeneralMgtIH: Codeunit "GeneralMgt IH";
        lo_cu_ItemMgt: Codeunit INHItemMgt;
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
        lo_de_UnitCost: Decimal;
    begin
        //C27°
        //TODO: Aulagern in Event und andere CU; Achtung: globale Variablen bo_TempPurch(über fnk_IsTempPurch) und op_ExchRateType(über fnk_GetPurchPriceAndDisc->FindPurchLineLineDisc) beachten
        //      Prüfen und umbauen, dass das weiterhin funktioniert
        with PurchaseLine do begin
            if Type = Type::Item then begin
                //START HO° ---------------------------------
                if lo_cu_PurchMgt.fnk_VendHasNetUnitCost(PurchaseHeader."Buy-from Vendor No.") then begin
                    if bo_TempPurch then PurchaseLine.fnk_SetPurchHdr("Document Type", "Document No.");   //C01°
                    lo_de_UnitCost := lo_cu_ItemMgt.FNK_NettoEPZuArtikel(Item."No.", WorkDate, Item."Vendor No.", "Unit of Measure Code");
                    Validate("Direct Unit Cost", lo_de_UnitCost);
                    exit;
                end;
                //STOP  HO° ---------------------------------
                //START Axx°.1 ---------------------------------
                if ("Currency Code" <> PurchasePrice."Currency Code") and (PurchasePrice."Direct Unit Cost" <> 0) then begin
                    lo_de_UnitCost := lo_cu_GeneralMgtIH.fnk_ExchCurr(WorkDate, PurchasePrice."Currency Code", "Currency Code", PurchasePrice."Direct Unit Cost", op_ExchRateType);
                    if lo_de_UnitCost <> "Direct Unit Cost" then begin
                        if bo_TempPurch then PurchaseLine.fnk_SetPurchHdr("Document Type", "Document No.");
                        Validate("Direct Unit Cost", lo_de_UnitCost);
                    end;
                end;
                //STOP  Axx°.1 ---------------------------------
            end;
        end;
    end;

    local procedure fnk_OnAfterFindPurchLineLineDisc(var PurchaseLine: Record "Purchase Line"; var PurchaseHeader: Record "Purchase Header"; var TempPurchLineDisc: Record "Purchase Line Discount" temporary)
    var
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
    begin
        //C27°
        //TODO: Aulagern in Event und andere CU
        with PurchaseLine do begin
            if Type = Type::Item then begin
                //START HO° ---------------------------------
                if lo_cu_PurchMgt.fnk_VendHasNetUnitCost(PurchaseHeader."Buy-from Vendor No.") then begin
                    Validate("Artikel Rabatt", 0);
                    Validate("Rabatt 3", 0);
                    Validate("Summe Grundrabatte", 0);
                    exit;
                end;
                //STOP  HO° ---------------------------------

                //START Axx° ---------------------------------
                //START C01° ---------------------------------
                //Achtung: Damit das funktioniert muss immer zuerst FindPurchLinePrice ausgeführt werden!
                if TempPurchPrice."Net Price" then begin
                    "Summe Grundrabatte" := 0;
                end else begin
                    //STOP  C01° ---------------------------------
                    "Summe Grundrabatte" := lo_cu_PurchMgt.FNK_GrundrabattvonPurchPrice("Buy-from Vendor No.", Item."No.", PurchaseLine);   //A94°
                end;   //C01°

                "Artikel Rabatt" := "Line Discount %";
                "Line Discount %" := lo_cu_PurchMgt.FNK_RabattEKZeileBerechnen(PurchaseLine);
                //STOP  Axx° ---------------------------------
            end;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, 7010, 'OnAfterFindReqLinePrice', '', false, false)]
    local procedure fnk_OnAfterFindReqLinePrice(var ReqLine: Record "Requisition Line"; var TempPurchasePrice: Record "Purchase Price" temporary; CalledByFieldNo: Integer)
    var
        lo_cu_ItemMgt: Codeunit INHItemMgt;
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
        lo_de_UnitCost: Decimal;
    begin
        //C27°
        //TODO: Aulagern in andere CU
        with ReqLine do begin
            if Type = Type::Item then begin
                "Unit Cost" := "Direct Unit Cost";
                //START HO° ---------------------------------
                if lo_cu_PurchMgt.fnk_VendHasNetUnitCost("Vendor No.") then begin
                    lo_de_UnitCost := lo_cu_ItemMgt.FNK_NettoEPZuArtikel(Item."No.", WorkDate, Item."Vendor No.", "Unit of Measure Code");
                    Validate("Direct Unit Cost", lo_de_UnitCost);
                    exit;
                end;
                //STOP  HO° ---------------------------------
            end;
        end;
    end;

    [EventSubscriber(ObjectType::Codeunit, 7010, 'OnAfterFindReqLineDisc', '', false, false)]
    local procedure fnk_OnAfterFindReqLineDisc(var ReqLine: Record "Requisition Line")
    var
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
    begin
        //C27°
        with ReqLine do begin
            if Type = Type::Item then begin
                //START HO° ---------------------------------
                if lo_cu_PurchMgt.fnk_VendHasNetUnitCost("Vendor No.") then begin
                    Validate("Line Discount %", 0);
                    Validate("Summe Grundrabatte", 0);
                    Validate(Artikelrabatt, 0);
                    exit;
                end;
                //STOP  HO° ---------------------------------

                //START Axx° ---------------------------------
                //START C01° ---------------------------------
                //Achtung: Damit das funktioniert muss immer zuerst FindReqLinePrice ausgeführt werden!
                if TempPurchPrice."Net Price" then begin
                    "Summe Grundrabatte" := 0;
                end else begin
                    //STOP  C01° ---------------------------------
                    "Summe Grundrabatte" := lo_cu_PurchMgt.FNK_GrundrabattPurchPriceBVO("Vendor No.", Item."No.", ReqLine);   //A94°
                end;   //C01°

                Artikelrabatt := "Line Discount %";
                "Line Discount %" := lo_cu_PurchMgt.FNK_RabattBVOBerechnen(ReqLine);
                //STOP  Axx° ---------------------------------
            end;
        end;
    end;
}

