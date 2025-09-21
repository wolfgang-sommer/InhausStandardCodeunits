codeunit 50137 INHSalesPriceCalcMgt
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // HO°           SSC  05.11.10  Gibt Debitoren die Netto EP bekommen
    // Axx°          RBI  11.08.08  Anpassungen übernommen.
    //                              Preise in anderen Währungen auch berücksichtigen + Umrechnung (FindSalesPrice/CopySalesPriceToSalesPrice)
    //               SSC  03.04.18  Nettopreissuche umgebaut; funktioniert gleich wie normale Preisliste
    //               SSC  10.02.25  Abfangen wenn Nettopreisliste gleich ist wie Preisliste, sonst Fehler beim einfügen des Preises in Temp-Tabelle
    // A22°.1        SSC  07.03.11  Der Preis aus der Artikel-Tabelle soll nie verwendet werden
    // A22°.2        SSC  07.03.11  Wird kein Preis zum "Preisdatum" gefunden, dann aktuellen nehmen (wenn vorhanden)
    // A22°.5        SSC  04.09.13  Neue fnk_GetSalesListPrice
    // A22°.6        SSC  10.06.14  Preis-KZ auch wieder auf Brutto stellen
    // A22°.10       SSC  08.02.21  Netto EP * Faktor für Mitarbeiter
    // A46°.1        SSC  15.10.15  Neue fnk_GetItemDiscGrpCustDisc
    // A65°          MBA  22.09.09  GU-Angebote werden ohne Rabatte und rein Brutto angeboten
    // A65°.1        SSC  23.02.12  Möglichkeit zur normalen Rabattberechnung
    // B02°.1        SSC  21.11.14  Kopfrabatt(=VK-Rabatt3) berücksichtigen
    // B38°.2        SSC  15.01.19  Mehr-Minder(=GU) Rabatt kann anders eingestellt werden
    // B72°          SSC  10.04.13  Artikelrabattgruppe von VK-Preis verwenden, nicht vom Artikel
    // B72°.1        SSC  20.11.14  Wenn ARG zu einem Datum nicht gefunden wird, dann die nächste nehmen nicht die aktuellste
    // C27°          SSC  03.04.18  Hooks
    // C46°.1        SSC  01.08.19  Neue fnk_GetRelevantSalesPrices
    // C83°          SSC  13.12.22  SST; Rabatte auf Kontakte bei SST nicht sperren
    // 
    // //TODO:
    //   - GU Überarbeiten(?)
    //   - Funktionen auslagern


    trigger OnRun()
    begin
    end;

    var
        GLSetup: Record "General Ledger Setup";
        Item: Record Item;
        ResPrice: Record "Resource Price";
        Res: Record Resource;
        Currency: Record Currency;
        Text000: Label '%1 is less than %2 in the %3.';
        Text010: Label 'Prices including VAT cannot be calculated when %1 is %2.';
        TempSalesPrice: Record "Sales Price" temporary;
        TempSalesLineDisc: Record "Sales Line Discount" temporary;
        LineDiscPerCent: Decimal;
        Qty: Decimal;
        AllowLineDisc: Boolean;
        AllowInvDisc: Boolean;
        VATPerCent: Decimal;
        PricesInclVAT: Boolean;
        VATCalcType: Option "Normal VAT","Reverse Charge VAT","Full VAT","Sales Tax";
        VATBusPostingGr: Code[20];
        QtyPerUOM: Decimal;
        PricesInCurrency: Boolean;
        CurrencyFactor: Decimal;
        ExchRateDate: Date;
        Text018: Label '%1 %2 is greater than %3 and was adjusted to %4.';
        FoundSalesPrice: Boolean;
        Text001: Label 'The %1 in the %2 must be same as in the %3.';
        TempTableErr: Label 'The table passed as a parameter must be temporary.';
        HideResUnitPriceMessage: Boolean;
        DateCaption: Text[30];
        "+++VAR_INHAUS+++": Boolean;
        co_CurrencyCode: Code[10];
        bo_ConvertPrice: Boolean;

    procedure FindSalesLinePrice(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; CalledByFieldNo: Integer)
    var
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindSalesLinePrice(SalesLine, SalesHeader, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with SalesLine do begin
            SetCurrency(
              SalesHeader."Currency Code", SalesHeader."Currency Factor", SalesHeaderExchDate(SalesHeader));
            SetVAT(SalesHeader."Prices Including VAT", "VAT %", "VAT Calculation Type", "VAT Bus. Posting Group");
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            SetLineDisc("Line Discount %", "Allow Line Disc.", "Allow Invoice Disc.");

            TestField("Qty. per Unit of Measure");
            if PricesInCurrency then
                SalesHeader.TestField("Currency Factor");

            case Type of
                Type::Item:
                    begin
                        Item.Get("No.");
                        SalesLinePriceExists(SalesHeader, SalesLine, false);
                        //START A22°.2 ---------------------------------
                        if TempSalesPrice.IsEmpty then begin
                            if (SalesHeader."Posting Date" <> WorkDate) or (SalesHeader."Order Date" <> WorkDate) then begin
                                SalesHeader."Posting Date" := WorkDate;
                                SalesHeader."Order Date" := WorkDate;
                                SalesLinePriceExists(SalesHeader, SalesLine, false);
                            end;
                        end;
                        //STOP  A22°.2 ---------------------------------
                        CalcBestUnitPrice(TempSalesPrice);
                        OnAfterFindSalesLineItemPrice(SalesLine, TempSalesPrice, FoundSalesPrice);
                        if FoundSalesPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                (CalledByFieldNo = FieldNo("Variant Code")))
                        then begin
                            "Allow Line Disc." := TempSalesPrice."Allow Line Disc.";
                            "Allow Invoice Disc." := TempSalesPrice."Allow Invoice Disc.";
                            "Unit Price" := TempSalesPrice."Unit Price";
                        end;
                        if not "Allow Line Disc." then
                            "Line Discount %" := 0;
                    end;
                Type::Resource:
                    begin
                        SetResPrice("No.", "Work Type Code", "Currency Code");
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Price", ResPrice);
                        OnAfterFindSalesLineResPrice(SalesLine, ResPrice);
                        ConvertPriceToVAT(false, '', '', ResPrice."Unit Price");
                        ConvertPriceLCYToFCY(ResPrice."Currency Code", ResPrice."Unit Price");
                        "Unit Price" := ResPrice."Unit Price" * "Qty. per Unit of Measure";
                    end;
            end;
            OnAfterFindSalesLinePrice(SalesLine, SalesHeader, TempSalesPrice, ResPrice, CalledByFieldNo);
        end;
        fnk_OnAfterFindSalesLinePrice(SalesHeader, SalesLine, CalledByFieldNo);   //C27°
    end;

    procedure FindItemJnlLinePrice(var ItemJnlLine: Record "Item Journal Line"; CalledByFieldNo: Integer)
    var
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindItemJnlLinePrice(ItemJnlLine, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with ItemJnlLine do begin
            SetCurrency('', 0, 0D);
            SetVAT(false, 0, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            TestField("Qty. per Unit of Measure");
            Item.Get("Item No.");

            FindSalesPrice(
              TempSalesPrice, '', '', '', '', "Item No.", "Variant Code",
              "Unit of Measure Code", '', "Posting Date", false);
            CalcBestUnitPrice(TempSalesPrice);
            if FoundSalesPrice or
               not ((CalledByFieldNo = FieldNo(Quantity)) or
                    (CalledByFieldNo = FieldNo("Variant Code")))
            then
                Validate("Unit Amount", TempSalesPrice."Unit Price");
            OnAfterFindItemJnlLinePrice(ItemJnlLine, TempSalesPrice, CalledByFieldNo, FoundSalesPrice);
        end;
    end;

    procedure FindServLinePrice(ServHeader: Record "Service Header"; var ServLine: Record "Service Line"; CalledByFieldNo: Integer)
    var
        ServCost: Record "Service Cost";
        Res: Record Resource;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindServLinePrice(ServLine, ServHeader, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with ServLine do begin
            ServHeader.Get("Document Type", "Document No.");
            if Type <> Type::" " then begin
                SetCurrency(
                  ServHeader."Currency Code", ServHeader."Currency Factor", ServHeaderExchDate(ServHeader));
                SetVAT(ServHeader."Prices Including VAT", "VAT %", "VAT Calculation Type", "VAT Bus. Posting Group");
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
                SetLineDisc("Line Discount %", "Allow Line Disc.", false);

                TestField("Qty. per Unit of Measure");
                if PricesInCurrency then
                    ServHeader.TestField("Currency Factor");
            end;

            case Type of
                Type::Item:
                    begin
                        ServLinePriceExists(ServHeader, ServLine, false);
                        CalcBestUnitPrice(TempSalesPrice);
                        if FoundSalesPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                (CalledByFieldNo = FieldNo("Variant Code")))
                        then begin
                            if "Line Discount Type" = "Line Discount Type"::"Line Disc." then
                                "Allow Line Disc." := TempSalesPrice."Allow Line Disc.";
                            "Unit Price" := TempSalesPrice."Unit Price";
                        end;
                        if not "Allow Line Disc." and ("Line Discount Type" = "Line Discount Type"::"Line Disc.") then
                            "Line Discount %" := 0;
                    end;
                Type::Resource:
                    begin
                        SetResPrice("No.", "Work Type Code", "Currency Code");
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Price", ResPrice);
                        OnAfterFindServLineResPrice(ServLine, ResPrice);
                        ConvertPriceToVAT(false, '', '', ResPrice."Unit Price");
                        ResPrice."Unit Price" := ResPrice."Unit Price" * "Qty. per Unit of Measure";
                        ConvertPriceLCYToFCY(ResPrice."Currency Code", ResPrice."Unit Price");
                        if (ResPrice."Unit Price" > ServHeader."Max. Labor Unit Price") and
                           (ServHeader."Max. Labor Unit Price" <> 0)
                        then begin
                            Res.Get("No.");
                            "Unit Price" := ServHeader."Max. Labor Unit Price";
                            if (HideResUnitPriceMessage = false) and
                               (CalledByFieldNo <> FieldNo(Quantity))
                            then
                                Message(
                                  StrSubstNo(
                                    Text018,
                                    Res.TableCaption, FieldCaption("Unit Price"),
                                    ServHeader.FieldCaption("Max. Labor Unit Price"),
                                    ServHeader."Max. Labor Unit Price"));
                            HideResUnitPriceMessage := true;
                        end else
                            "Unit Price" := ResPrice."Unit Price";
                    end;
                Type::Cost:
                    begin
                        ServCost.Get("No.");

                        ConvertPriceToVAT(false, '', '', ServCost."Default Unit Price");
                        ConvertPriceLCYToFCY('', ServCost."Default Unit Price");
                        "Unit Price" := ServCost."Default Unit Price";
                    end;
            end;
            OnAfterFindServLinePrice(ServLine, ServHeader, TempSalesPrice, ResPrice, ServCost, CalledByFieldNo);
        end;
    end;

    procedure FindSalesLineLineDisc(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    var
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindSalesLineLineDisc(SalesLine, SalesHeader, IsHandled);
        if IsHandled then
            exit;

        //START-A65°---------------------------
        if (SalesHeader.Angebotsart in [SalesHeader.Angebotsart::"GU-Vorlage", SalesHeader.Angebotsart::"GU-Angebot"])
            and not (SalesHeader."Standard Disc. Calc.")   // A65°.1
        then
            exit;
        //STOP-A65°----------------------------
        with SalesLine do begin
            SetCurrency(SalesHeader."Currency Code", 0, 0D);
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            IsHandled := false;
            OnFindSalesLineLineDiscOnBeforeCalcLineDisc(SalesHeader, SalesLine, TempSalesLineDisc, Qty, QtyPerUOM, IsHandled);
            if not IsHandled then
                if Type = Type::Item then begin
                    SalesLineLineDiscExists(SalesHeader, SalesLine, false);
                    CalcBestLineDisc(TempSalesLineDisc);
                    "Line Discount %" := TempSalesLineDisc."Line Discount %";
                end;

            OnAfterFindSalesLineLineDisc(SalesLine, SalesHeader, TempSalesLineDisc);
        end;
        fnk_OnAfterFindSalesLineLineDisc(SalesHeader, SalesLine);   //C27°
    end;

    procedure FindServLineDisc(ServHeader: Record "Service Header"; var ServLine: Record "Service Line")
    var
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindServLineDisc(ServHeader, ServLine, IsHandled);
        if IsHandled then
            exit;

        with ServLine do begin
            SetCurrency(ServHeader."Currency Code", 0, 0D);
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            TestField("Qty. per Unit of Measure");

            if Type = Type::Item then begin
                Item.Get("No.");
                FindSalesLineDisc(
                  TempSalesLineDisc, "Bill-to Customer No.", ServHeader."Contact No.",
                  "Customer Disc. Group", '', "No.", Item."Item Disc. Group", "Variant Code",
                  "Unit of Measure Code", ServHeader."Currency Code", ServHeader."Order Date", false);
                CalcBestLineDisc(TempSalesLineDisc);
                "Line Discount %" := TempSalesLineDisc."Line Discount %";
            end;
            if Type in [Type::Resource, Type::Cost, Type::"G/L Account"] then begin
                "Line Discount %" := 0;
                "Line Discount Amount" :=
                  Round(
                    Round(CalcChargeableQty * "Unit Price", Currency."Amount Rounding Precision") *
                    "Line Discount %" / 100, Currency."Amount Rounding Precision");
                "Inv. Discount Amount" := 0;
                "Inv. Disc. Amount to Invoice" := 0;
            end;
            OnAfterFindServLineDisc(ServLine, ServHeader, TempSalesLineDisc);
        end;
    end;

    procedure FindStdItemJnlLinePrice(var StdItemJnlLine: Record "Standard Item Journal Line"; CalledByFieldNo: Integer)
    var
        IsHandled: Boolean;
    begin
        IsHandled := true;
        OnBeforeFindStdItemJnlLinePrice(StdItemJnlLine, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with StdItemJnlLine do begin
            SetCurrency('', 0, 0D);
            SetVAT(false, 0, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            TestField("Qty. per Unit of Measure");
            Item.Get("Item No.");

            FindSalesPrice(
              TempSalesPrice, '', '', '', '', "Item No.", "Variant Code",
              "Unit of Measure Code", '', WorkDate, false);
            CalcBestUnitPrice(TempSalesPrice);
            if FoundSalesPrice or
               not ((CalledByFieldNo = FieldNo(Quantity)) or
                    (CalledByFieldNo = FieldNo("Variant Code")))
            then
                Validate("Unit Amount", TempSalesPrice."Unit Price");
            OnAfterFindStdItemJnlLinePrice(StdItemJnlLine, TempSalesPrice, CalledByFieldNo);
        end;
    end;

    procedure FindAnalysisReportPrice(ItemNo: Code[20]; Date: Date): Decimal
    var
        UnitPrice: Decimal;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindAnalysisReportPrice(ItemNo, Date, UnitPrice, IsHandled);
        if IsHandled then
            exit(UnitPrice);

        SetCurrency('', 0, 0D);
        SetVAT(false, 0, 0, '');
        SetUoM(0, 1);
        Item.Get(ItemNo);

        FindSalesPrice(TempSalesPrice, '', '', '', '', ItemNo, '', '', '', Date, false);
        CalcBestUnitPrice(TempSalesPrice);
        if FoundSalesPrice then
            exit(TempSalesPrice."Unit Price");
        exit(Item."Unit Price");
    end;

    procedure CalcBestUnitPrice(var SalesPrice: Record "Sales Price")
    var
        BestSalesPrice: Record "Sales Price";
        BestSalesPriceFound: Boolean;
    begin
        OnBeforeCalcBestUnitPrice(SalesPrice);

        with SalesPrice do begin
            FoundSalesPrice := FindSet;
            if FoundSalesPrice then
                repeat
                    if IsInMinQty("Unit of Measure Code", "Minimum Quantity") then begin
                        ConvertPriceToVAT(
                          "Price Includes VAT", Item."VAT Prod. Posting Group",
                          "VAT Bus. Posting Gr. (Price)", "Unit Price");
                        ConvertPriceToUoM("Unit of Measure Code", "Unit Price");
                        ConvertPriceLCYToFCY("Currency Code", "Unit Price");

                        case true of
                            ((BestSalesPrice."Currency Code" = '') and ("Currency Code" <> '')) or
                            ((BestSalesPrice."Variant Code" = '') and ("Variant Code" <> '')):
                                begin
                                    BestSalesPrice := SalesPrice;
                                    BestSalesPriceFound := true;
                                end;
                            ((BestSalesPrice."Currency Code" = '') or ("Currency Code" <> '')) and
                          ((BestSalesPrice."Variant Code" = '') or ("Variant Code" <> '')):
                                if (BestSalesPrice."Unit Price" = 0) or
                                   (CalcLineAmount(BestSalesPrice) > CalcLineAmount(SalesPrice))
                                then begin
                                    BestSalesPrice := SalesPrice;
                                    BestSalesPriceFound := true;
                                end;
                        end;
                    end;
                until Next = 0;
        end;

        OnAfterCalcBestUnitPrice(SalesPrice);

        // No price found in agreement
        if not BestSalesPriceFound then begin
            ConvertPriceToVAT(
              Item."Price Includes VAT", Item."VAT Prod. Posting Group",
              Item."VAT Bus. Posting Gr. (Price)", Item."Unit Price");
            ConvertPriceToUoM('', Item."Unit Price");
            ConvertPriceLCYToFCY('', Item."Unit Price");

            Clear(BestSalesPrice);
            //A22°.1:BestSalesPrice."Unit Price" := Item."Unit Price";
            BestSalesPrice."Allow Line Disc." := AllowLineDisc;
            BestSalesPrice."Allow Invoice Disc." := AllowInvDisc;
            OnAfterCalcBestUnitPriceAsItemUnitPrice(BestSalesPrice, Item);
        end;

        SalesPrice := BestSalesPrice;
    end;

    procedure CalcBestLineDisc(var SalesLineDisc: Record "Sales Line Discount")
    var
        BestSalesLineDisc: Record "Sales Line Discount";
    begin
        with SalesLineDisc do begin
            if FindSet then
                repeat
                    if IsInMinQty("Unit of Measure Code", "Minimum Quantity") then
                        case true of
                            ((BestSalesLineDisc."Currency Code" = '') and ("Currency Code" <> '')) or
                          ((BestSalesLineDisc."Variant Code" = '') and ("Variant Code" <> '')):
                                BestSalesLineDisc := SalesLineDisc;
                            ((BestSalesLineDisc."Currency Code" = '') or ("Currency Code" <> '')) and
                          ((BestSalesLineDisc."Variant Code" = '') or ("Variant Code" <> '')):
                                if BestSalesLineDisc."Line Discount %" < "Line Discount %" then
                                    BestSalesLineDisc := SalesLineDisc;
                        end;
                until Next = 0;
        end;

        SalesLineDisc := BestSalesLineDisc;
    end;

    procedure FindSalesPrice(var ToSalesPrice: Record "Sales Price"; CustNo: Code[20]; ContNo: Code[20]; CustPriceGrCode: Code[10]; CampaignNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    var
        FromSalesPrice: Record "Sales Price";
        TempTargetCampaignGr: Record "Campaign Target Group" temporary;
    begin
        if not ToSalesPrice.IsTemporary then
            Error(TempTableErr);

        ToSalesPrice.Reset;
        ToSalesPrice.DeleteAll;

        OnBeforeFindSalesPrice(
          ToSalesPrice, FromSalesPrice, QtyPerUOM, Qty, CustNo, ContNo, CustPriceGrCode, CampaignNo,
          ItemNo, VariantCode, UOM, CurrencyCode, StartingDate, ShowAll);

        with FromSalesPrice do begin
            SetRange("Item No.", ItemNo);
            SetFilter("Variant Code", '%1|%2', VariantCode, '');
            SetFilter("Ending Date", '%1|>=%2', 0D, StartingDate);
            if not ShowAll then begin
                //START Axx° ---------------------------------
                //SETFILTER("Currency Code",'%1|%2',CurrencyCode,'');
                co_CurrencyCode := CurrencyCode;
                bo_ConvertPrice := true;
                //STOP  Axx° ---------------------------------
                if UOM <> '' then
                    SetFilter("Unit of Measure Code", '%1|%2', UOM, '');
                SetRange("Starting Date", 0D, StartingDate);
            end;

            SetRange("Sales Type", "Sales Type"::"All Customers");
            SetRange("Sales Code");
            CopySalesPriceToSalesPrice(FromSalesPrice, ToSalesPrice);

            if CustNo <> '' then begin
                SetRange("Sales Type", "Sales Type"::Customer);
                SetRange("Sales Code", CustNo);
                CopySalesPriceToSalesPrice(FromSalesPrice, ToSalesPrice);
            end;

            if CustPriceGrCode <> '' then begin
                SetRange("Sales Type", "Sales Type"::"Customer Price Group");
                SetRange("Sales Code", CustPriceGrCode);
                CopySalesPriceToSalesPrice(FromSalesPrice, ToSalesPrice);
            end;

            if not ((CustNo = '') and (ContNo = '') and (CampaignNo = '')) then begin
                SetRange("Sales Type", "Sales Type"::Campaign);
                if ActivatedCampaignExists(TempTargetCampaignGr, CustNo, ContNo, CampaignNo) then
                    repeat
                        SetRange("Sales Code", TempTargetCampaignGr."Campaign No.");
                        CopySalesPriceToSalesPrice(FromSalesPrice, ToSalesPrice);
                    until TempTargetCampaignGr.Next = 0;
            end;
        end;

        OnAfterFindSalesPrice(
          ToSalesPrice, FromSalesPrice, QtyPerUOM, Qty, CustNo, ContNo, CustPriceGrCode, CampaignNo,
          ItemNo, VariantCode, UOM, CurrencyCode, StartingDate, ShowAll);
        fnk_OnAfterFindSalesPrice(FromSalesPrice, ToSalesPrice, CustNo);   //C27°
    end;

    procedure FindSalesLineDisc(var ToSalesLineDisc: Record "Sales Line Discount"; CustNo: Code[20]; ContNo: Code[20]; CustDiscGrCode: Code[20]; CampaignNo: Code[20]; ItemNo: Code[20]; ItemDiscGrCode: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    var
        FromSalesLineDisc: Record "Sales Line Discount";
        TempCampaignTargetGr: Record "Campaign Target Group" temporary;
        InclCampaigns: Boolean;
    begin
        OnBeforeFindSalesLineDisc(
          ToSalesLineDisc, CustNo, ContNo, CustDiscGrCode, CampaignNo, ItemNo, ItemDiscGrCode, VariantCode, UOM,
          CurrencyCode, StartingDate, ShowAll);

        fnk_OnBeforeFindSalesLineDisc(ItemNo, ItemDiscGrCode, StartingDate);   //C27°
        with FromSalesLineDisc do begin
            SetFilter("Ending Date", '%1|>=%2', 0D, StartingDate);
            SetFilter("Variant Code", '%1|%2', VariantCode, '');
            OnFindSalesLineDiscOnAfterSetFilters(FromSalesLineDisc);
            if not ShowAll then begin
                SetRange("Starting Date", 0D, StartingDate);
                SetFilter("Currency Code", '%1|%2', CurrencyCode, '');
                if UOM <> '' then
                    SetFilter("Unit of Measure Code", '%1|%2', UOM, '');
            end;

            ToSalesLineDisc.Reset;
            ToSalesLineDisc.DeleteAll;
            for "Sales Type" := "Sales Type"::Customer to "Sales Type"::Campaign do
                if ("Sales Type" = "Sales Type"::"All Customers") or
                   (("Sales Type" = "Sales Type"::Customer) and (CustNo <> '')) or
                   (("Sales Type" = "Sales Type"::"Customer Disc. Group") and (CustDiscGrCode <> '')) or
                   (("Sales Type" = "Sales Type"::Campaign) and
                    not ((CustNo = '') and (ContNo = '') and (CampaignNo = '')))
                then begin
                    InclCampaigns := false;

                    SetRange("Sales Type", "Sales Type");
                    case "Sales Type" of
                        "Sales Type"::"All Customers":
                            SetRange("Sales Code");
                        "Sales Type"::Customer:
                            SetRange("Sales Code", CustNo);
                        "Sales Type"::"Customer Disc. Group":
                            SetRange("Sales Code", CustDiscGrCode);
                        "Sales Type"::Campaign:
                            begin
                                InclCampaigns := ActivatedCampaignExists(TempCampaignTargetGr, CustNo, ContNo, CampaignNo);
                                SetRange("Sales Code", TempCampaignTargetGr."Campaign No.");
                            end;
                    end;

                    repeat
                        SetRange(Type, Type::Item);
                        SetRange(Code, ItemNo);
                        CopySalesDiscToSalesDisc(FromSalesLineDisc, ToSalesLineDisc);

                        if ItemDiscGrCode <> '' then begin
                            SetRange(Type, Type::"Item Disc. Group");
                            SetRange(Code, ItemDiscGrCode);
                            CopySalesDiscToSalesDisc(FromSalesLineDisc, ToSalesLineDisc);
                        end;

                        if InclCampaigns then begin
                            InclCampaigns := TempCampaignTargetGr.Next <> 0;
                            SetRange("Sales Code", TempCampaignTargetGr."Campaign No.");
                        end;
                    until not InclCampaigns;
                end;
        end;

        OnAfterFindSalesLineDisc(
          ToSalesLineDisc, CustNo, ContNo, CustDiscGrCode, CampaignNo, ItemNo, ItemDiscGrCode, VariantCode, UOM,
          CurrencyCode, StartingDate, ShowAll);
    end;

    procedure CopySalesPrice(var SalesPrice: Record "Sales Price")
    begin
        SalesPrice.DeleteAll;
        CopySalesPriceToSalesPrice(TempSalesPrice, SalesPrice);
    end;

    local procedure CopySalesPriceToSalesPrice(var FromSalesPrice: Record "Sales Price"; var ToSalesPrice: Record "Sales Price")
    var
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_GeneralMgtIH: Codeunit "GeneralMgt IH";
    begin
        with ToSalesPrice do begin
            if FromSalesPrice.FindSet then
                repeat
                    ToSalesPrice := FromSalesPrice;
                    //START Axx° ---------------------------------
                    if bo_ConvertPrice and not ("Currency Code" in [co_CurrencyCode, '']) then begin
                        "Unit Price" := Round(lo_cu_GeneralMgtIH.fnk_ExchCurr(WorkDate, "Currency Code", co_CurrencyCode, "Unit Price", 0), 0.01);
                        "Currency Code" := co_CurrencyCode;
                    end;
                    //STOP  Axx° ---------------------------------
                    Insert;
                until FromSalesPrice.Next = 0;
        end;
    end;

    local procedure CopySalesDiscToSalesDisc(var FromSalesLineDisc: Record "Sales Line Discount"; var ToSalesLineDisc: Record "Sales Line Discount")
    begin
        with ToSalesLineDisc do begin
            if FromSalesLineDisc.FindSet then
                repeat
                    ToSalesLineDisc := FromSalesLineDisc;
                    Insert;
                until FromSalesLineDisc.Next = 0;
        end;
    end;

    procedure SetResPrice(Code2: Code[20]; WorkTypeCode: Code[10]; CurrencyCode: Code[10])
    begin
        with ResPrice do begin
            Init;
            Code := Code2;
            "Work Type Code" := WorkTypeCode;
            "Currency Code" := CurrencyCode;
        end;
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

    local procedure SetVAT(PriceInclVAT2: Boolean; VATPerCent2: Decimal; VATCalcType2: Option; VATBusPostingGr2: Code[20])
    begin
        PricesInclVAT := PriceInclVAT2;
        VATPerCent := VATPerCent2;
        VATCalcType := VATCalcType2;
        VATBusPostingGr := VATBusPostingGr2;
    end;

    local procedure SetUoM(Qty2: Decimal; QtyPerUoM2: Decimal)
    begin
        Qty := Qty2;
        QtyPerUOM := QtyPerUoM2;
    end;

    local procedure SetLineDisc(LineDiscPerCent2: Decimal; AllowLineDisc2: Boolean; AllowInvDisc2: Boolean)
    begin
        LineDiscPerCent := LineDiscPerCent2;
        AllowLineDisc := AllowLineDisc2;
        AllowInvDisc := AllowInvDisc2;
    end;

    local procedure IsInMinQty(UnitofMeasureCode: Code[10]; MinQty: Decimal): Boolean
    begin
        if UnitofMeasureCode = '' then
            exit(MinQty <= QtyPerUOM * Qty);
        exit(MinQty <= Qty);
    end;

    local procedure ConvertPriceToVAT(FromPricesInclVAT: Boolean; FromVATProdPostingGr: Code[20]; FromVATBusPostingGr: Code[20]; var UnitPrice: Decimal)
    var
        VATPostingSetup: Record "VAT Posting Setup";
    begin
        if FromPricesInclVAT then begin
            VATPostingSetup.Get(FromVATBusPostingGr, FromVATProdPostingGr);
            OnBeforeConvertPriceToVAT(VATPostingSetup);

            case VATPostingSetup."VAT Calculation Type" of
                VATPostingSetup."VAT Calculation Type"::"Reverse Charge VAT":
                    VATPostingSetup."VAT %" := 0;
                VATPostingSetup."VAT Calculation Type"::"Sales Tax":
                    Error(
                      Text010,
                      VATPostingSetup.FieldCaption("VAT Calculation Type"),
                      VATPostingSetup."VAT Calculation Type");
            end;

            case VATCalcType of
                VATCalcType::"Normal VAT",
                VATCalcType::"Full VAT",
                VATCalcType::"Sales Tax":
                    begin
                        if PricesInclVAT then begin
                            if VATBusPostingGr <> FromVATBusPostingGr then
                                UnitPrice := UnitPrice * (100 + VATPerCent) / (100 + VATPostingSetup."VAT %");
                        end else
                            UnitPrice := UnitPrice / (1 + VATPostingSetup."VAT %" / 100);
                    end;
                VATCalcType::"Reverse Charge VAT":
                    UnitPrice := UnitPrice / (1 + VATPostingSetup."VAT %" / 100);
            end;
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

    local procedure CalcLineAmount(SalesPrice: Record "Sales Price"): Decimal
    begin
        with SalesPrice do begin
            if "Allow Line Disc." then
                exit("Unit Price" * (1 - LineDiscPerCent / 100));
            exit("Unit Price");
        end;
    end;

    procedure GetSalesLinePrice(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    begin
        SalesLinePriceExists(SalesHeader, SalesLine, true);

        with SalesLine do
            if PAGE.RunModal(PAGE::"Get Sales Price", TempSalesPrice) = ACTION::LookupOK then begin
                SetVAT(
                  SalesHeader."Prices Including VAT", "VAT %", "VAT Calculation Type", "VAT Bus. Posting Group");
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
                SetCurrency(
                  SalesHeader."Currency Code", SalesHeader."Currency Factor", SalesHeaderExchDate(SalesHeader));

                if not IsInMinQty(TempSalesPrice."Unit of Measure Code", TempSalesPrice."Minimum Quantity") then
                    Error(
                      Text000,
                      FieldCaption(Quantity),
                      TempSalesPrice.FieldCaption("Minimum Quantity"),
                      TempSalesPrice.TableCaption);
                if not (TempSalesPrice."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempSalesPrice.TableCaption);
                if not (TempSalesPrice."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempSalesPrice.TableCaption);
                if TempSalesPrice."Starting Date" > SalesHeaderStartDate(SalesHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempSalesPrice.FieldCaption("Starting Date"),
                      TempSalesPrice.TableCaption);

                ConvertPriceToVAT(
                  TempSalesPrice."Price Includes VAT", Item."VAT Prod. Posting Group",
                  TempSalesPrice."VAT Bus. Posting Gr. (Price)", TempSalesPrice."Unit Price");
                ConvertPriceToUoM(TempSalesPrice."Unit of Measure Code", TempSalesPrice."Unit Price");
                ConvertPriceLCYToFCY(TempSalesPrice."Currency Code", TempSalesPrice."Unit Price");

                "Allow Invoice Disc." := TempSalesPrice."Allow Invoice Disc.";
                "Allow Line Disc." := TempSalesPrice."Allow Line Disc.";
                if not "Allow Line Disc." then
                    "Line Discount %" := 0;

                Validate("Unit Price", TempSalesPrice."Unit Price");
            end;

        OnAfterGetSalesLinePrice(SalesHeader, SalesLine, TempSalesPrice);
    end;

    procedure GetSalesLineLineDisc(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    begin
        OnBeforeGetSalesLineLineDisc(SalesHeader, SalesLine);

        SalesLineLineDiscExists(SalesHeader, SalesLine, true);

        with SalesLine do
            if PAGE.RunModal(PAGE::"Get Sales Line Disc.", TempSalesLineDisc) = ACTION::LookupOK then begin
                SetCurrency(SalesHeader."Currency Code", 0, 0D);
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

                if not IsInMinQty(TempSalesLineDisc."Unit of Measure Code", TempSalesLineDisc."Minimum Quantity")
                then
                    Error(
                      Text000, FieldCaption(Quantity),
                      TempSalesLineDisc.FieldCaption("Minimum Quantity"),
                      TempSalesLineDisc.TableCaption);
                if not (TempSalesLineDisc."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempSalesLineDisc.TableCaption);
                if not (TempSalesLineDisc."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempSalesLineDisc.TableCaption);
                if TempSalesLineDisc."Starting Date" > SalesHeaderStartDate(SalesHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempSalesLineDisc.FieldCaption("Starting Date"),
                      TempSalesLineDisc.TableCaption);

                TestField("Allow Line Disc.");
                Validate("Line Discount %", TempSalesLineDisc."Line Discount %");
            end;

        OnAfterGetSalesLineLineDisc(SalesLine, TempSalesLineDisc);
    end;

    procedure SalesLinePriceExists(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; ShowAll: Boolean): Boolean
    var
        IsHandled: Boolean;
    begin
        with SalesLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                IsHandled := false;
                OnBeforeSalesLinePriceExists(
                  SalesLine, SalesHeader, TempSalesPrice, Currency, CurrencyFactor,
                  SalesHeaderStartDate(SalesHeader, DateCaption), Qty, QtyPerUOM, ShowAll, IsHandled);
                if not IsHandled then begin
                    FindSalesPrice(
                      TempSalesPrice, GetCustNoForSalesHeader(SalesHeader), SalesHeader."Bill-to Contact No.",
                      "Customer Price Group", '', "No.", "Variant Code", "Unit of Measure Code",
                      SalesHeader."Currency Code", SalesHeaderStartDate(SalesHeader, DateCaption), ShowAll);
                    OnAfterSalesLinePriceExists(SalesLine, SalesHeader, TempSalesPrice, ShowAll);
                end;
                exit(TempSalesPrice.FindFirst);
            end;
        exit(false);
    end;

    procedure SalesLineLineDiscExists(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; ShowAll: Boolean): Boolean
    var
        IsHandled: Boolean;
    begin
        with SalesLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                IsHandled := false;
                OnBeforeSalesLineLineDiscExists(
                  SalesLine, SalesHeader, TempSalesLineDisc, SalesHeaderStartDate(SalesHeader, DateCaption),
                  Qty, QtyPerUOM, ShowAll, IsHandled);
                if not IsHandled then begin
                    FindSalesLineDisc(
                      TempSalesLineDisc, GetCustNoForSalesHeader(SalesHeader), SalesHeader."Bill-to Contact No.",
                      "Customer Disc. Group", '', "No.", Item."Item Disc. Group", "Variant Code", "Unit of Measure Code",
                      SalesHeader."Currency Code", SalesHeaderStartDate(SalesHeader, DateCaption), ShowAll);
                    OnAfterSalesLineLineDiscExists(SalesLine, SalesHeader, TempSalesLineDisc, ShowAll);
                end;
                exit(TempSalesLineDisc.FindFirst);
            end;
        exit(false);
    end;

    procedure GetServLinePrice(ServHeader: Record "Service Header"; var ServLine: Record "Service Line")
    begin
        ServLinePriceExists(ServHeader, ServLine, true);

        with ServLine do
            if PAGE.RunModal(PAGE::"Get Sales Price", TempSalesPrice) = ACTION::LookupOK then begin
                SetVAT(
                  ServHeader."Prices Including VAT", "VAT %", "VAT Calculation Type", "VAT Bus. Posting Group");
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
                SetCurrency(
                  ServHeader."Currency Code", ServHeader."Currency Factor", ServHeaderExchDate(ServHeader));

                if not IsInMinQty(TempSalesPrice."Unit of Measure Code", TempSalesPrice."Minimum Quantity") then
                    Error(
                      Text000,
                      FieldCaption(Quantity),
                      TempSalesPrice.FieldCaption("Minimum Quantity"),
                      TempSalesPrice.TableCaption);
                if not (TempSalesPrice."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempSalesPrice.TableCaption);
                if not (TempSalesPrice."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempSalesPrice.TableCaption);
                if TempSalesPrice."Starting Date" > ServHeaderStartDate(ServHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempSalesPrice.FieldCaption("Starting Date"),
                      TempSalesPrice.TableCaption);

                ConvertPriceToVAT(
                  TempSalesPrice."Price Includes VAT", Item."VAT Prod. Posting Group",
                  TempSalesPrice."VAT Bus. Posting Gr. (Price)", TempSalesPrice."Unit Price");
                ConvertPriceToUoM(TempSalesPrice."Unit of Measure Code", TempSalesPrice."Unit Price");
                ConvertPriceLCYToFCY(TempSalesPrice."Currency Code", TempSalesPrice."Unit Price");

                "Allow Invoice Disc." := TempSalesPrice."Allow Invoice Disc.";
                "Allow Line Disc." := TempSalesPrice."Allow Line Disc.";
                if not "Allow Line Disc." then
                    "Line Discount %" := 0;

                Validate("Unit Price", TempSalesPrice."Unit Price");
                ConfirmAdjPriceLineChange;
            end;
    end;

    procedure GetServLineLineDisc(ServHeader: Record "Service Header"; var ServLine: Record "Service Line")
    begin
        ServLineLineDiscExists(ServHeader, ServLine, true);

        with ServLine do
            if PAGE.RunModal(PAGE::"Get Sales Line Disc.", TempSalesLineDisc) = ACTION::LookupOK then begin
                SetCurrency(ServHeader."Currency Code", 0, 0D);
                SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

                if not IsInMinQty(TempSalesLineDisc."Unit of Measure Code", TempSalesLineDisc."Minimum Quantity")
                then
                    Error(
                      Text000, FieldCaption(Quantity),
                      TempSalesLineDisc.FieldCaption("Minimum Quantity"),
                      TempSalesLineDisc.TableCaption);
                if not (TempSalesLineDisc."Currency Code" in ["Currency Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Currency Code"),
                      TableCaption,
                      TempSalesLineDisc.TableCaption);
                if not (TempSalesLineDisc."Unit of Measure Code" in ["Unit of Measure Code", '']) then
                    Error(
                      Text001,
                      FieldCaption("Unit of Measure Code"),
                      TableCaption,
                      TempSalesLineDisc.TableCaption);
                if TempSalesLineDisc."Starting Date" > ServHeaderStartDate(ServHeader, DateCaption) then
                    Error(
                      Text000,
                      DateCaption,
                      TempSalesLineDisc.FieldCaption("Starting Date"),
                      TempSalesLineDisc.TableCaption);

                TestField("Allow Line Disc.");
                CheckLineDiscount(TempSalesLineDisc."Line Discount %");
                Validate("Line Discount %", TempSalesLineDisc."Line Discount %");
                ConfirmAdjPriceLineChange;
            end;
    end;

    local procedure GetCustNoForSalesHeader(SalesHeader: Record "Sales Header"): Code[20]
    var
        CustNo: Code[20];
    begin
        CustNo := SalesHeader."Bill-to Customer No.";
        OnGetCustNoForSalesHeader(SalesHeader, CustNo);
        exit(CustNo);
    end;

    local procedure ServLinePriceExists(ServHeader: Record "Service Header"; var ServLine: Record "Service Line"; ShowAll: Boolean): Boolean
    var
        IsHandled: Boolean;
    begin
        with ServLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                IsHandled := false;
                OnBeforeServLinePriceExists(ServLine, ServHeader, TempSalesPrice, ShowAll, IsHandled);
                if not IsHandled then
                    FindSalesPrice(
                      TempSalesPrice, "Bill-to Customer No.", ServHeader."Bill-to Contact No.",
                      "Customer Price Group", '', "No.", "Variant Code", "Unit of Measure Code",
                      ServHeader."Currency Code", ServHeaderStartDate(ServHeader, DateCaption), ShowAll);
                OnAfterServLinePriceExists(ServLine);
                exit(TempSalesPrice.Find('-'));
            end;
        exit(false);
    end;

    local procedure ServLineLineDiscExists(ServHeader: Record "Service Header"; var ServLine: Record "Service Line"; ShowAll: Boolean): Boolean
    begin
        with ServLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                OnBeforeServLineLineDiscExists(ServLine, ServHeader);
                FindSalesLineDisc(
                  TempSalesLineDisc, "Bill-to Customer No.", ServHeader."Bill-to Contact No.",
                  "Customer Disc. Group", '', "No.", Item."Item Disc. Group", "Variant Code", "Unit of Measure Code",
                  ServHeader."Currency Code", ServHeaderStartDate(ServHeader, DateCaption), ShowAll);
                OnAfterServLineLineDiscExists(ServLine);
                exit(TempSalesLineDisc.Find('-'));
            end;
        exit(false);
    end;

    procedure ActivatedCampaignExists(var ToCampaignTargetGr: Record "Campaign Target Group"; CustNo: Code[20]; ContNo: Code[20]; CampaignNo: Code[20]): Boolean
    var
        FromCampaignTargetGr: Record "Campaign Target Group";
        Cont: Record Contact;
    begin
        if not ToCampaignTargetGr.IsTemporary then
            Error(TempTableErr);

        with FromCampaignTargetGr do begin
            ToCampaignTargetGr.Reset;
            ToCampaignTargetGr.DeleteAll;

            if CampaignNo <> '' then begin
                ToCampaignTargetGr."Campaign No." := CampaignNo;
                ToCampaignTargetGr.Insert;
            end else begin
                SetRange(Type, Type::Customer);
                SetRange("No.", CustNo);
                if FindSet then
                    repeat
                        ToCampaignTargetGr := FromCampaignTargetGr;
                        ToCampaignTargetGr.Insert;
                    until Next = 0
                else
                    if Cont.Get(ContNo) then begin
                        SetRange(Type, Type::Contact);
                        SetRange("No.", Cont."Company No.");
                        if FindSet then
                            repeat
                                ToCampaignTargetGr := FromCampaignTargetGr;
                                ToCampaignTargetGr.Insert;
                            until Next = 0;
                    end;
            end;
            exit(ToCampaignTargetGr.FindFirst);
        end;
    end;

    local procedure SalesHeaderExchDate(SalesHeader: Record "Sales Header"): Date
    begin
        with SalesHeader do begin
            if "Posting Date" <> 0D then
                exit("Posting Date");
            exit(WorkDate);
        end;
    end;

    local procedure SalesHeaderStartDate(var SalesHeader: Record "Sales Header"; var DateCaption: Text[30]): Date
    begin
        with SalesHeader do
            if "Document Type" in ["Document Type"::Invoice, "Document Type"::"Credit Memo"] then begin
                DateCaption := FieldCaption("Posting Date");
                exit("Posting Date")
            end else begin
                DateCaption := FieldCaption("Order Date");
                exit("Order Date");
            end;
    end;

    local procedure ServHeaderExchDate(ServHeader: Record "Service Header"): Date
    begin
        with ServHeader do begin
            if ("Document Type" = "Document Type"::Quote) and
               ("Posting Date" = 0D)
            then
                exit(WorkDate);
            exit("Posting Date");
        end;
    end;

    local procedure ServHeaderStartDate(ServHeader: Record "Service Header"; var DateCaption: Text[30]): Date
    begin
        with ServHeader do
            if "Document Type" in ["Document Type"::Invoice, "Document Type"::"Credit Memo"] then begin
                DateCaption := FieldCaption("Posting Date");
                exit("Posting Date")
            end else begin
                DateCaption := FieldCaption("Order Date");
                exit("Order Date");
            end;
    end;

    procedure NoOfSalesLinePrice(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; ShowAll: Boolean): Integer
    begin
        if SalesLinePriceExists(SalesHeader, SalesLine, ShowAll) then
            exit(TempSalesPrice.Count);
    end;

    procedure NoOfSalesLineLineDisc(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; ShowAll: Boolean): Integer
    begin
        if SalesLineLineDiscExists(SalesHeader, SalesLine, ShowAll) then
            exit(TempSalesLineDisc.Count);
    end;

    procedure NoOfServLinePrice(ServHeader: Record "Service Header"; var ServLine: Record "Service Line"; ShowAll: Boolean): Integer
    begin
        if ServLinePriceExists(ServHeader, ServLine, ShowAll) then
            exit(TempSalesPrice.Count);
    end;

    procedure NoOfServLineLineDisc(ServHeader: Record "Service Header"; var ServLine: Record "Service Line"; ShowAll: Boolean): Integer
    begin
        if ServLineLineDiscExists(ServHeader, ServLine, ShowAll) then
            exit(TempSalesLineDisc.Count);
    end;

    procedure FindJobPlanningLinePrice(var JobPlanningLine: Record "Job Planning Line"; CalledByFieldNo: Integer)
    var
        Job: Record Job;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindJobPlanningLinePrice(JobPlanningLine, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with JobPlanningLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Planning Date");
            SetVAT(false, 0, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            SetLineDisc(0, true, true);

            case Type of
                Type::Item:
                    begin
                        Job.Get("Job No.");
                        Item.Get("No.");
                        TestField("Qty. per Unit of Measure");
                        FindSalesPrice(
                          TempSalesPrice, Job."Bill-to Customer No.", Job."Bill-to Contact No.",
                          Job."Customer Price Group", '', "No.", "Variant Code", "Unit of Measure Code",
                          Job."Currency Code", "Planning Date", false);
                        CalcBestUnitPrice(TempSalesPrice);
                        if FoundSalesPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                (CalledByFieldNo = FieldNo("Location Code")) or
                                (CalledByFieldNo = FieldNo("Variant Code")))
                        then begin
                            "Unit Price" := TempSalesPrice."Unit Price";
                            AllowLineDisc := TempSalesPrice."Allow Line Disc.";
                        end;
                    end;
                Type::Resource:
                    begin
                        Job.Get("Job No.");
                        SetResPrice("No.", "Work Type Code", "Currency Code");
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Price", ResPrice);
                        OnAfterFindJobPlanningLineResPrice(JobPlanningLine, ResPrice);
                        ConvertPriceLCYToFCY(ResPrice."Currency Code", ResPrice."Unit Price");
                        "Unit Price" := ResPrice."Unit Price" * "Qty. per Unit of Measure";
                    end;
            end;
        end;
        JobPlanningLineFindJTPrice(JobPlanningLine);
    end;

    procedure JobPlanningLineFindJTPrice(var JobPlanningLine: Record "Job Planning Line")
    var
        JobItemPrice: Record "Job Item Price";
        JobResPrice: Record "Job Resource Price";
        JobGLAccPrice: Record "Job G/L Account Price";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeJobPlanningLineFindJTPrice(JobPlanningLine, IsHandled);
        if IsHandled then
            exit;

        with JobPlanningLine do
            case Type of
                Type::Item:
                    begin
                        JobItemPrice.SetRange("Job No.", "Job No.");
                        JobItemPrice.SetRange("Item No.", "No.");
                        JobItemPrice.SetRange("Variant Code", "Variant Code");
                        JobItemPrice.SetRange("Unit of Measure Code", "Unit of Measure Code");
                        JobItemPrice.SetRange("Currency Code", "Currency Code");
                        JobItemPrice.SetRange("Job Task No.", "Job Task No.");
                        if JobItemPrice.FindFirst then
                            CopyJobItemPriceToJobPlanLine(JobPlanningLine, JobItemPrice)
                        else begin
                            JobItemPrice.SetRange("Job Task No.", ' ');
                            if JobItemPrice.FindFirst then
                                CopyJobItemPriceToJobPlanLine(JobPlanningLine, JobItemPrice);
                        end;

                        if JobItemPrice.IsEmpty or (not JobItemPrice."Apply Job Discount") then
                            FindJobPlanningLineLineDisc(JobPlanningLine);
                    end;
                Type::Resource:
                    begin
                        Res.Get("No.");
                        JobResPrice.SetRange("Job No.", "Job No.");
                        JobResPrice.SetRange("Currency Code", "Currency Code");
                        JobResPrice.SetRange("Job Task No.", "Job Task No.");
                        case true of
                            JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::Resource):
                                CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                            JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::"Group(Resource)"):
                                CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                            JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::All):
                                CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                            else begin
                                JobResPrice.SetRange("Job Task No.", '');
                                case true of
                                    JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::Resource):
                                        CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                                    JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::"Group(Resource)"):
                                        CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                                    JobPlanningLineFindJobResPrice(JobPlanningLine, JobResPrice, JobResPrice.Type::All):
                                        CopyJobResPriceToJobPlanLine(JobPlanningLine, JobResPrice);
                                end;
                            end;
                        end;
                    end;
                Type::"G/L Account":
                    begin
                        JobGLAccPrice.SetRange("Job No.", "Job No.");
                        JobGLAccPrice.SetRange("G/L Account No.", "No.");
                        JobGLAccPrice.SetRange("Currency Code", "Currency Code");
                        JobGLAccPrice.SetRange("Job Task No.", "Job Task No.");
                        if JobGLAccPrice.FindFirst then
                            CopyJobGLAccPriceToJobPlanLine(JobPlanningLine, JobGLAccPrice)
                        else begin
                            JobGLAccPrice.SetRange("Job Task No.", '');
                            if JobGLAccPrice.FindFirst then
                                CopyJobGLAccPriceToJobPlanLine(JobPlanningLine, JobGLAccPrice);
                        end;
                    end;
            end;
    end;

    local procedure CopyJobItemPriceToJobPlanLine(var JobPlanningLine: Record "Job Planning Line"; JobItemPrice: Record "Job Item Price")
    begin
        with JobPlanningLine do begin
            if JobItemPrice."Apply Job Price" then begin
                "Unit Price" := JobItemPrice."Unit Price";
                "Cost Factor" := JobItemPrice."Unit Cost Factor";
            end;
            if JobItemPrice."Apply Job Discount" then
                "Line Discount %" := JobItemPrice."Line Discount %";
        end;
    end;

    local procedure CopyJobResPriceToJobPlanLine(var JobPlanningLine: Record "Job Planning Line"; JobResPrice: Record "Job Resource Price")
    begin
        with JobPlanningLine do begin
            if JobResPrice."Apply Job Price" then begin
                "Unit Price" := JobResPrice."Unit Price" * "Qty. per Unit of Measure";
                "Cost Factor" := JobResPrice."Unit Cost Factor";
            end;
            if JobResPrice."Apply Job Discount" then
                "Line Discount %" := JobResPrice."Line Discount %";
        end;
    end;

    local procedure JobPlanningLineFindJobResPrice(var JobPlanningLine: Record "Job Planning Line"; var JobResPrice: Record "Job Resource Price"; PriceType: Option Resource,"Group(Resource)",All): Boolean
    begin
        case PriceType of
            PriceType::Resource:
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::Resource);
                    JobResPrice.SetRange("Work Type Code", JobPlanningLine."Work Type Code");
                    JobResPrice.SetRange(Code, JobPlanningLine."No.");
                    exit(JobResPrice.Find('-'));
                end;
            PriceType::"Group(Resource)":
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::"Group(Resource)");
                    JobResPrice.SetRange(Code, Res."Resource Group No.");
                    exit(FindJobResPrice(JobResPrice, JobPlanningLine."Work Type Code"));
                end;
            PriceType::All:
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::All);
                    JobResPrice.SetRange(Code);
                    exit(FindJobResPrice(JobResPrice, JobPlanningLine."Work Type Code"));
                end;
        end;
    end;

    local procedure CopyJobGLAccPriceToJobPlanLine(var JobPlanningLine: Record "Job Planning Line"; JobGLAccPrice: Record "Job G/L Account Price")
    begin
        with JobPlanningLine do begin
            "Unit Cost" := JobGLAccPrice."Unit Cost";
            "Unit Price" := JobGLAccPrice."Unit Price" * "Qty. per Unit of Measure";
            "Cost Factor" := JobGLAccPrice."Unit Cost Factor";
            "Line Discount %" := JobGLAccPrice."Line Discount %";
        end;
    end;

    procedure FindJobJnlLinePrice(var JobJnlLine: Record "Job Journal Line"; CalledByFieldNo: Integer)
    var
        Job: Record Job;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeFindJobJnlLinePrice(JobJnlLine, CalledByFieldNo, IsHandled);
        if IsHandled then
            exit;

        with JobJnlLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Posting Date");
            SetVAT(false, 0, 0, '');
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");

            case Type of
                Type::Item:
                    begin
                        Item.Get("No.");
                        TestField("Qty. per Unit of Measure");
                        Job.Get("Job No.");

                        FindSalesPrice(
                          TempSalesPrice, Job."Bill-to Customer No.", Job."Bill-to Contact No.",
                          "Customer Price Group", '', "No.", "Variant Code", "Unit of Measure Code",
                          "Currency Code", "Posting Date", false);
                        CalcBestUnitPrice(TempSalesPrice);
                        if FoundSalesPrice or
                           not ((CalledByFieldNo = FieldNo(Quantity)) or
                                (CalledByFieldNo = FieldNo("Variant Code")))
                        then
                            "Unit Price" := TempSalesPrice."Unit Price";
                    end;
                Type::Resource:
                    begin
                        Job.Get("Job No.");
                        SetResPrice("No.", "Work Type Code", "Currency Code");
                        CODEUNIT.Run(CODEUNIT::"Resource-Find Price", ResPrice);
                        OnAfterFindJobJnlLineResPrice(JobJnlLine, ResPrice);
                        ConvertPriceLCYToFCY(ResPrice."Currency Code", ResPrice."Unit Price");
                        "Unit Price" := ResPrice."Unit Price" * "Qty. per Unit of Measure";
                    end;
            end;
        end;
        JobJnlLineFindJTPrice(JobJnlLine);
    end;

    local procedure JobJnlLineFindJobResPrice(var JobJnlLine: Record "Job Journal Line"; var JobResPrice: Record "Job Resource Price"; PriceType: Option Resource,"Group(Resource)",All): Boolean
    begin
        case PriceType of
            PriceType::Resource:
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::Resource);
                    JobResPrice.SetRange("Work Type Code", JobJnlLine."Work Type Code");
                    JobResPrice.SetRange(Code, JobJnlLine."No.");
                    exit(JobResPrice.Find('-'));
                end;
            PriceType::"Group(Resource)":
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::"Group(Resource)");
                    JobResPrice.SetRange(Code, Res."Resource Group No.");
                    exit(FindJobResPrice(JobResPrice, JobJnlLine."Work Type Code"));
                end;
            PriceType::All:
                begin
                    JobResPrice.SetRange(Type, JobResPrice.Type::All);
                    JobResPrice.SetRange(Code);
                    exit(FindJobResPrice(JobResPrice, JobJnlLine."Work Type Code"));
                end;
        end;
    end;

    local procedure CopyJobResPriceToJobJnlLine(var JobJnlLine: Record "Job Journal Line"; JobResPrice: Record "Job Resource Price")
    begin
        with JobJnlLine do begin
            if JobResPrice."Apply Job Price" then begin
                "Unit Price" := JobResPrice."Unit Price" * "Qty. per Unit of Measure";
                "Cost Factor" := JobResPrice."Unit Cost Factor";
            end;
            if JobResPrice."Apply Job Discount" then
                "Line Discount %" := JobResPrice."Line Discount %";
        end;
    end;

    local procedure CopyJobGLAccPriceToJobJnlLine(var JobJnlLine: Record "Job Journal Line"; JobGLAccPrice: Record "Job G/L Account Price")
    begin
        with JobJnlLine do begin
            "Unit Cost" := JobGLAccPrice."Unit Cost";
            "Unit Price" := JobGLAccPrice."Unit Price" * "Qty. per Unit of Measure";
            "Cost Factor" := JobGLAccPrice."Unit Cost Factor";
            "Line Discount %" := JobGLAccPrice."Line Discount %";
        end;
    end;

    local procedure JobJnlLineFindJTPrice(var JobJnlLine: Record "Job Journal Line")
    var
        JobItemPrice: Record "Job Item Price";
        JobResPrice: Record "Job Resource Price";
        JobGLAccPrice: Record "Job G/L Account Price";
    begin
        with JobJnlLine do
            case Type of
                Type::Item:
                    begin
                        JobItemPrice.SetRange("Job No.", "Job No.");
                        JobItemPrice.SetRange("Item No.", "No.");
                        JobItemPrice.SetRange("Variant Code", "Variant Code");
                        JobItemPrice.SetRange("Unit of Measure Code", "Unit of Measure Code");
                        JobItemPrice.SetRange("Currency Code", "Currency Code");
                        JobItemPrice.SetRange("Job Task No.", "Job Task No.");
                        if JobItemPrice.FindFirst then
                            CopyJobItemPriceToJobJnlLine(JobJnlLine, JobItemPrice)
                        else begin
                            JobItemPrice.SetRange("Job Task No.", ' ');
                            if JobItemPrice.FindFirst then
                                CopyJobItemPriceToJobJnlLine(JobJnlLine, JobItemPrice);
                        end;
                        if JobItemPrice.IsEmpty or (not JobItemPrice."Apply Job Discount") then
                            FindJobJnlLineLineDisc(JobJnlLine);
                        OnAfterJobJnlLineFindJTPriceItem(JobJnlLine);
                    end;
                Type::Resource:
                    begin
                        Res.Get("No.");
                        JobResPrice.SetRange("Job No.", "Job No.");
                        JobResPrice.SetRange("Currency Code", "Currency Code");
                        JobResPrice.SetRange("Job Task No.", "Job Task No.");
                        case true of
                            JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::Resource):
                                CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                            JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::"Group(Resource)"):
                                CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                            JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::All):
                                CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                            else begin
                                JobResPrice.SetRange("Job Task No.", '');
                                case true of
                                    JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::Resource):
                                        CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                                    JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::"Group(Resource)"):
                                        CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                                    JobJnlLineFindJobResPrice(JobJnlLine, JobResPrice, JobResPrice.Type::All):
                                        CopyJobResPriceToJobJnlLine(JobJnlLine, JobResPrice);
                                end;
                            end;
                        end;
                        OnAfterJobJnlLineFindJTPriceResource(JobJnlLine);
                    end;
                Type::"G/L Account":
                    begin
                        JobGLAccPrice.SetRange("Job No.", "Job No.");
                        JobGLAccPrice.SetRange("G/L Account No.", "No.");
                        JobGLAccPrice.SetRange("Currency Code", "Currency Code");
                        JobGLAccPrice.SetRange("Job Task No.", "Job Task No.");
                        if JobGLAccPrice.FindFirst then
                            CopyJobGLAccPriceToJobJnlLine(JobJnlLine, JobGLAccPrice)
                        else begin
                            JobGLAccPrice.SetRange("Job Task No.", '');
                            if JobGLAccPrice.FindFirst then;
                            CopyJobGLAccPriceToJobJnlLine(JobJnlLine, JobGLAccPrice);
                        end;
                        OnAfterJobJnlLineFindJTPriceGLAccount(JobJnlLine);
                    end;
            end;
    end;

    local procedure CopyJobItemPriceToJobJnlLine(var JobJnlLine: Record "Job Journal Line"; JobItemPrice: Record "Job Item Price")
    begin
        with JobJnlLine do begin
            if JobItemPrice."Apply Job Price" then begin
                "Unit Price" := JobItemPrice."Unit Price";
                "Cost Factor" := JobItemPrice."Unit Cost Factor";
            end;
            if JobItemPrice."Apply Job Discount" then
                "Line Discount %" := JobItemPrice."Line Discount %";
        end;
    end;

    local procedure FindJobPlanningLineLineDisc(var JobPlanningLine: Record "Job Planning Line")
    begin
        with JobPlanningLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Planning Date");
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            TestField("Qty. per Unit of Measure");
            if Type = Type::Item then begin
                JobPlanningLineLineDiscExists(JobPlanningLine, false);
                CalcBestLineDisc(TempSalesLineDisc);
                if AllowLineDisc then
                    "Line Discount %" := TempSalesLineDisc."Line Discount %"
                else
                    "Line Discount %" := 0;
            end;
        end;

        OnAfterFindJobPlanningLineLineDisc(JobPlanningLine, TempSalesLineDisc);
    end;

    local procedure JobPlanningLineLineDiscExists(var JobPlanningLine: Record "Job Planning Line"; ShowAll: Boolean): Boolean
    var
        Job: Record Job;
    begin
        with JobPlanningLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                Job.Get("Job No.");
                OnBeforeJobPlanningLineLineDiscExists(JobPlanningLine);
                FindSalesLineDisc(
                  TempSalesLineDisc, Job."Bill-to Customer No.", Job."Bill-to Contact No.",
                  Job."Customer Disc. Group", '', "No.", Item."Item Disc. Group", "Variant Code", "Unit of Measure Code",
                  "Currency Code", JobPlanningLineStartDate(JobPlanningLine, DateCaption), ShowAll);
                OnAfterJobPlanningLineLineDiscExists(JobPlanningLine);
                exit(TempSalesLineDisc.Find('-'));
            end;
        exit(false);
    end;

    local procedure JobPlanningLineStartDate(JobPlanningLine: Record "Job Planning Line"; var DateCaption: Text[30]): Date
    begin
        DateCaption := JobPlanningLine.FieldCaption("Planning Date");
        exit(JobPlanningLine."Planning Date");
    end;

    local procedure FindJobJnlLineLineDisc(var JobJnlLine: Record "Job Journal Line")
    begin
        with JobJnlLine do begin
            SetCurrency("Currency Code", "Currency Factor", "Posting Date");
            SetUoM(Abs(Quantity), "Qty. per Unit of Measure");
            TestField("Qty. per Unit of Measure");
            if Type = Type::Item then begin
                JobJnlLineLineDiscExists(JobJnlLine, false);
                CalcBestLineDisc(TempSalesLineDisc);
                "Line Discount %" := TempSalesLineDisc."Line Discount %";
            end;
        end;

        OnAfterFindJobJnlLineLineDisc(JobJnlLine, TempSalesLineDisc);
    end;

    local procedure JobJnlLineLineDiscExists(var JobJnlLine: Record "Job Journal Line"; ShowAll: Boolean): Boolean
    var
        Job: Record Job;
    begin
        with JobJnlLine do
            if (Type = Type::Item) and Item.Get("No.") then begin
                Job.Get("Job No.");
                OnBeforeJobJnlLineLineDiscExists(JobJnlLine);
                FindSalesLineDisc(
                  TempSalesLineDisc, Job."Bill-to Customer No.", Job."Bill-to Contact No.",
                  Job."Customer Disc. Group", '', "No.", Item."Item Disc. Group", "Variant Code", "Unit of Measure Code",
                  "Currency Code", JobJnlLineStartDate(JobJnlLine, DateCaption), ShowAll);
                OnAfterJobJnlLineLineDiscExists(JobJnlLine);
                exit(TempSalesLineDisc.Find('-'));
            end;
        exit(false);
    end;

    local procedure JobJnlLineStartDate(JobJnlLine: Record "Job Journal Line"; var DateCaption: Text[30]): Date
    begin
        DateCaption := JobJnlLine.FieldCaption("Posting Date");
        exit(JobJnlLine."Posting Date");
    end;

    local procedure FindJobResPrice(var JobResPrice: Record "Job Resource Price"; WorkTypeCode: Code[10]): Boolean
    begin
        JobResPrice.SetRange("Work Type Code", WorkTypeCode);
        if JobResPrice.FindFirst then
            exit(true);
        JobResPrice.SetRange("Work Type Code", '');
        exit(JobResPrice.FindFirst);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalcBestUnitPrice(var SalesPrice: Record "Sales Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCalcBestUnitPriceAsItemUnitPrice(var SalesPrice: Record "Sales Price"; var Item: Record Item)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindItemJnlLinePrice(var ItemJournalLine: Record "Item Journal Line"; var SalesPrice: Record "Sales Price"; CalledByFieldNo: Integer; FoundSalesPrice: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobJnlLineResPrice(var JobJournalLine: Record "Job Journal Line"; var ResourcePrice: Record "Resource Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobJnlLineLineDisc(var JobJournalLine: Record "Job Journal Line"; var TempSalesLineDisc: Record "Sales Line Discount" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobPlanningLineLineDisc(var JobPlanningLine: Record "Job Planning Line"; var TempSalesLineDisc: Record "Sales Line Discount" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindJobPlanningLineResPrice(var JobPlanningLine: Record "Job Planning Line"; var ResourcePrice: Record "Resource Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindStdItemJnlLinePrice(var StdItemJnlLine: Record "Standard Item Journal Line"; var SalesPrice: Record "Sales Price"; CalledByFieldNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesLinePrice(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var SalesPrice: Record "Sales Price"; var ResourcePrice: Record "Resource Price"; CalledByFieldNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesLineLineDisc(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var SalesLineDiscount: Record "Sales Line Discount")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesPrice(var ToSalesPrice: Record "Sales Price"; var FromSalesPrice: Record "Sales Price"; QtyPerUOM: Decimal; Qty: Decimal; CustNo: Code[20]; ContNo: Code[20]; CustPriceGrCode: Code[10]; CampaignNo: Code[20]; ItemNo: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesLineItemPrice(var SalesLine: Record "Sales Line"; var TempSalesPrice: Record "Sales Price" temporary; var FoundSalesPrice: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesLineResPrice(var SalesLine: Record "Sales Line"; var ResPrice: Record "Resource Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindSalesLineDisc(var ToSalesLineDisc: Record "Sales Line Discount"; CustNo: Code[20]; ContNo: Code[20]; CustDiscGrCode: Code[20]; CampaignNo: Code[20]; ItemNo: Code[20]; ItemDiscGrCode: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindServLinePrice(var ServiceLine: Record "Service Line"; var ServiceHeader: Record "Service Header"; var SalesPrice: Record "Sales Price"; var ResourcePrice: Record "Resource Price"; var ServiceCost: Record "Service Cost"; CalledByFieldNo: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindServLineResPrice(var ServiceLine: Record "Service Line"; var ResPrice: Record "Resource Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindServLineDisc(var ServiceLine: Record "Service Line"; var ServiceHeader: Record "Service Header"; var SalesLineDiscount: Record "Sales Line Discount")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetSalesLinePrice(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; var TempSalesPrice: Record "Sales Price" temporary)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetSalesLineLineDisc(var SalesLine: Record "Sales Line"; var SalesLineDiscount: Record "Sales Line Discount")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobJnlLineFindJTPriceGLAccount(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobJnlLineFindJTPriceItem(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobJnlLineFindJTPriceResource(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobJnlLineLineDiscExists(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterJobPlanningLineLineDiscExists(var JobPlanningLine: Record "Job Planning Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSalesLineLineDiscExists(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var TempSalesLineDisc: Record "Sales Line Discount" temporary; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSalesLinePriceExists(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var TempSalesPrice: Record "Sales Price" temporary; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterServLinePriceExists(var ServiceLine: Record "Service Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterServLineLineDiscExists(var ServiceLine: Record "Service Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCalcBestUnitPrice(var SalesPrice: Record "Sales Price")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConvertPriceToVAT(var VATPostingSetup: Record "VAT Posting Setup")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindAnalysisReportPrice(ItemNo: Code[20]; Date: Date; var UnitPrice: Decimal; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindItemJnlLinePrice(var ItemJournalLine: Record "Item Journal Line"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindJobJnlLinePrice(var JobJournalLine: Record "Job Journal Line"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindJobPlanningLinePrice(var JobPlanningLine: Record "Job Planning Line"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindSalesPrice(var ToSalesPrice: Record "Sales Price"; var FromSalesPrice: Record "Sales Price"; var QtyPerUOM: Decimal; var Qty: Decimal; var CustNo: Code[20]; var ContNo: Code[20]; var CustPriceGrCode: Code[10]; var CampaignNo: Code[20]; var ItemNo: Code[20]; var VariantCode: Code[10]; var UOM: Code[10]; var CurrencyCode: Code[10]; var StartingDate: Date; var ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindSalesLinePrice(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindSalesLineDisc(var ToSalesLineDisc: Record "Sales Line Discount"; CustNo: Code[20]; ContNo: Code[20]; CustDiscGrCode: Code[20]; CampaignNo: Code[20]; ItemNo: Code[20]; ItemDiscGrCode: Code[20]; VariantCode: Code[10]; UOM: Code[10]; CurrencyCode: Code[10]; StartingDate: Date; ShowAll: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindSalesLineLineDisc(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindServLinePrice(var ServiceLine: Record "Service Line"; ServiceHeader: Record "Service Header"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindServLineDisc(var ServiceHeader: Record "Service Header"; var ServiceLine: Record "Service Line"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeFindStdItemJnlLinePrice(var StandardItemJournalLine: Record "Standard Item Journal Line"; CalledByFieldNo: Integer; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetSalesLineLineDisc(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeJobJnlLineLineDiscExists(var JobJournalLine: Record "Job Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeJobPlanningLineLineDiscExists(var JobPlanningLine: Record "Job Planning Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeJobPlanningLineFindJTPrice(var JobPlanningLine: Record "Job Planning Line"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesLineLineDiscExists(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var TempSalesLineDisc: Record "Sales Line Discount" temporary; StartingDate: Date; Qty: Decimal; QtyPerUOM: Decimal; ShowAll: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesLinePriceExists(var SalesLine: Record "Sales Line"; var SalesHeader: Record "Sales Header"; var TempSalesPrice: Record "Sales Price" temporary; Currency: Record Currency; CurrencyFactor: Decimal; StartingDate: Date; Qty: Decimal; QtyPerUOM: Decimal; ShowAll: Boolean; var InHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeServLinePriceExists(var ServiceLine: Record "Service Line"; var ServiceHeader: Record "Service Header"; var TempSalesPrice: Record "Sales Price" temporary; ShowAll: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeServLineLineDiscExists(var ServiceLine: Record "Service Line"; var ServiceHeader: Record "Service Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetCustNoForSalesHeader(var SalesHeader: Record "Sales Header"; var CustomerNo: Code[20])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFindSalesLineDiscOnAfterSetFilters(var SalesLineDiscount: Record "Sales Line Discount")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFindSalesLineLineDiscOnBeforeCalcLineDisc(var SalesHeader: Record "Sales Header"; SalesLine: Record "Sales Line"; var TempSalesLineDiscount: Record "Sales Line Discount" temporary; Qty: Decimal; QtyPerUOM: Decimal; var IsHandled: Boolean)
    begin
    end;

    local procedure "+++FNK_INHAUS+++"()
    begin
    end;

    [Scope('Internal')]
    procedure fnk_GetItemDiscGrp(par_co_ItemNo: Code[20]; par_da_Date: Date; par_te_CompanyName: Text[30]) rv_co_ItemDiscGrp: Code[20]
    var
        lo_re_InitTable: Record "INHInitTable";
        lo_re_Item: Record Item;
        lo_re_SalesPrice: Record "Sales Price";
    begin
        // *** Aktuelle Artikelrabattgruppe   //B72°
        //     Annahme: Es gibt zu einem Datum immer nur eine Rabattgruppe pro Artikel/Mandant
        //       Es gibt immer min. einen Preis für Preisliste 1(GmbH) und 2(AG) für jeden Artikel
        //       Bestätigt von LMAR und SMIC
        //     sollte also immer passen, wenn man den genauen VK-Preis-Record braucht dann fnk_GetSalesPrice verwenden

        if par_te_CompanyName = '' then
            par_te_CompanyName := CompanyName;

        lo_re_InitTable.Get(par_te_CompanyName);

        lo_re_SalesPrice.SetRange("Item No.", par_co_ItemNo);
        lo_re_SalesPrice.SetRange("Sales Type", lo_re_SalesPrice."Sales Type"::"Customer Price Group");
        lo_re_SalesPrice.SetRange("Sales Code", lo_re_InitTable.Init_Preisliste);
        lo_re_SalesPrice.SetFilter("Ending Date", '%1|>=%2', 0D, par_da_Date);
        lo_re_SalesPrice.SetRange("Starting Date", 0D, par_da_Date);
        lo_re_SalesPrice.SetFilter("Item Disc. Group", '<>%1', '');
        if lo_re_SalesPrice.FindLast then begin
            rv_co_ItemDiscGrp := lo_re_SalesPrice."Item Disc. Group";
        end else begin
            lo_re_SalesPrice.SetRange("Ending Date");
            //START B72°.1 ---------------------------------
            lo_re_SalesPrice.SetFilter("Starting Date", '%1..', par_da_Date);
            if lo_re_SalesPrice.FindFirst then begin
                rv_co_ItemDiscGrp := lo_re_SalesPrice."Item Disc. Group";
            end else begin
                //STOP  B72°.1 ---------------------------------
                lo_re_SalesPrice.SetRange("Starting Date");
                if lo_re_SalesPrice.FindLast then begin
                    rv_co_ItemDiscGrp := lo_re_SalesPrice."Item Disc. Group";
                end else begin
                    //Div z.B. hat keinen Preis -> Info immer noch nur auf Artikel
                    if lo_re_Item.Get(par_co_ItemNo) then begin
                        rv_co_ItemDiscGrp := lo_re_Item."Item Disc. Group";
                    end else begin
                        rv_co_ItemDiscGrp := '';
                    end;
                end;
            end;   //B72°.1
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetItemDiscGrpCustDisc(par_co_ItemDiscGrp: Code[20]; par_co_CustNo: Code[20]; par_da_ToDate: Date; var par_re_SalesLineDisc: Record "Sales Line Discount")
    var
        lo_re_Cust: Record Customer;
        lo_re_SalesLineDisc: Record "Sales Line Discount";
    begin
        // *** Der Rabatt eines Kunden zu einer Artikelrabattgruppe   //A46°.1
        Clear(par_re_SalesLineDisc);
        if not lo_re_Cust.Get(par_co_CustNo) then
            exit;
        with lo_re_SalesLineDisc do begin
            SetRange(Type, Type::"Item Disc. Group");
            SetRange(Code, par_co_ItemDiscGrp);
            SetRange("Sales Type", "Sales Type"::Customer);
            SetRange("Sales Code", par_co_CustNo);
            SetFilter("Ending Date", '%1|>=%2', 0D, par_da_ToDate);
            SetRange("Starting Date", 0D, par_da_ToDate);
            if FindLast then begin
                par_re_SalesLineDisc := lo_re_SalesLineDisc;
            end;
            SetRange("Sales Type", "Sales Type"::"Customer Disc. Group");
            SetRange("Sales Code", lo_re_Cust."Customer Disc. Group");
            if FindLast then begin
                if par_re_SalesLineDisc."Line Discount %" < "Line Discount %" then begin
                    par_re_SalesLineDisc := lo_re_SalesLineDisc;
                end;
            end;
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetPriceDateT36(par_re_SalesHdr: Record "Sales Header") rv_da_PriceDate: Date
    begin
        // *** Datum für die Preisfindung   //B72°
        with par_re_SalesHdr do begin
            if "Document Type" in ["Document Type"::Invoice, "Document Type"::"Credit Memo"] then
                rv_da_PriceDate := "Posting Date"
            else
                rv_da_PriceDate := "Order Date";
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetPriceDateT5107(par_re_SalesHdrArch: Record "Sales Header Archive") rv_da_PriceDate: Date
    begin
        // *** Datum für die Preisfindung   //B72°
        with par_re_SalesHdrArch do begin
            if "Document Type" in ["Document Type"::Invoice, "Document Type"::"Credit Memo"] then
                rv_da_PriceDate := "Posting Date"
            else
                rv_da_PriceDate := "Order Date";
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetRelevantSalesPrices(var par_re_TempSalesPrice: Record "Sales Price" temporary)
    begin
        // *** Gibt Preise zurück die zuvor in FindSalesPrice gefunden wurden   //C46°.1
        with TempSalesPrice do begin
            if FindSet(false, false) then begin
                repeat
                    par_re_TempSalesPrice := TempSalesPrice;
                    if par_re_TempSalesPrice.Insert(false) then;
                until Next = 0;
            end;
        end;
    end;

    [Scope('Internal')]
    procedure fnk_GetSalesListPrice(par_re_Item: Record Item; par_te_Companyname: Text[30]) rv_de_Price: Decimal
    var
        lo_re_InitTable: Record "INHInitTable";
        lo_re_SalesPrice: Record "Sales Price";
    begin
        // *** Aktuell gültiger Listenpreis(=Artikelkarte->Reiter Fakturierung->VK-Preis)   //A22°.5

        if par_te_Companyname <> '' then begin
            lo_re_InitTable.Get(par_te_Companyname);
        end else begin
            lo_re_InitTable.Get(CompanyName);
        end;

        lo_re_SalesPrice.Reset;
        lo_re_SalesPrice.SetRange("Item No.", par_re_Item."No.");
        lo_re_SalesPrice.SetRange("Sales Type", lo_re_SalesPrice."Sales Type"::"Customer Price Group");
        lo_re_SalesPrice.SetRange("Sales Code", lo_re_InitTable.Init_Preisliste);
        lo_re_SalesPrice.SetFilter("Ending Date", '%1|>=%2', 0D, WorkDate);
        lo_re_SalesPrice.SetRange("Starting Date", 0D, WorkDate);
        lo_re_SalesPrice.SetRange("Minimum Quantity", 0);
        lo_re_SalesPrice.SetRange("Unit of Measure Code", par_re_Item."Base Unit of Measure");
        if lo_re_SalesPrice.FindLast then begin
            rv_de_Price := lo_re_SalesPrice."Unit Price";
        end;
    end;

    local procedure fnk_OnBeforeFindSalesLineDisc(ItemNo: Code[20]; var ItemDiscGrCode: Code[20]; StartingDate: Date)
    begin
        //C27°
        ItemDiscGrCode := fnk_GetItemDiscGrp(ItemNo, StartingDate, '');   //B72°
    end;

    local procedure fnk_OnAfterFindSalesLineLineDisc(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    var
        lo_cu_ICMgt: Codeunit ICMgt;
    begin
        //C27°
        with SalesLine do begin
            //START Axx° ---------------------------------
            if Type = Type::Item then begin
                "Line Discount %" := (Round(100 - (100 * (1 - TempSalesLineDisc."Line Discount %" / 100) * (1 - "VK-Rabatt3" / 100)), 0.00001));   //B02°.1
                "VK-Rabatt1" := TempSalesLineDisc."VK-Rabatt1";
                "VK-Rabatt2" := TempSalesLineDisc."VK-Rabatt2";
                if (SalesHeader."Sell-to Customer No." = '') then begin
                    if lo_cu_ICMgt.fnk_IsCompanyInhausClassic(CompanyName) then begin   //C83°
                        Clear("Line Discount %");
                        Clear("VK-Rabatt1");
                        Clear("VK-Rabatt2");
                    end;   //C83°
                end;
            end;
            //STOP  Axx° ---------------------------------
        end;
    end;

    local procedure fnk_OnAfterFindSalesLinePrice(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; CalledByFieldNo: Integer)
    var
        lo_re_Cust: Record Customer;
        lo_cu_ItemMgt: Codeunit ItemMgt;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_cu_PreisfindungKundeArtikel: Codeunit "Preisfindung Kunde-Artikel";
        lo_de_PriceFactor: Decimal;
        lo_de_UnitPrice: Decimal;
    begin
        //C27°
        with SalesLine do begin

            if Type = Type::Item then begin
                //START HO° ---------------------------------
                //START A22°.10 ---------------------------------
                //IF lo_cu_SalesMgt.fnk_CustGetsNetUnitCost(SalesHeader."Sell-to Customer No.") THEN BEGIN
                if lo_cu_SalesMgt.fnk_CustGetsNetUnitCostFactor(SalesHeader."Sell-to Customer No.", SalesLine."No.", lo_de_PriceFactor) then begin
                    //STOP  A22°.10 ---------------------------------
                    lo_de_UnitPrice := lo_cu_ItemMgt.FNK_NettoEPZuArtikel(Item."No.", WorkDate, Item."Vendor No.", "Unit of Measure Code");
                    //START A22°.10 ---------------------------------
                    lo_de_UnitPrice := Round(lo_de_UnitPrice * lo_de_PriceFactor, 0.01);
                    if lo_de_UnitPrice > 0 then begin
                        SalesLine.SuspendStatusCheck(true);
                        SalesLine.SetSalesHeader(SalesHeader);
                        //STOP  A22°.10 ---------------------------------
                        Validate("Unit Price", lo_de_UnitPrice);
                        Validate("Preis-KZ", "Preis-KZ"::Netto);
                        Validate("VK-Rabatt1", 0);
                        Validate("VK-Rabatt2", 0);
                        Validate("VK-Rabatt3", 0);
                        exit;
                    end;   //A22°.10
                end;
                //STOP  HO° ---------------------------------

                //START-A65°---------------------------
                if (SalesHeader.Angebotsart in [SalesHeader.Angebotsart::"GU-Vorlage", SalesHeader.Angebotsart::"GU-Angebot"])
                    and not (SalesHeader."Standard Disc. Calc.")   // A65°.1
                then begin
                    "Preis-KZ" := "Preis-KZ"::Brutto;
                    if (SalesLine.Positionsart = SalesLine.Positionsart::Aufpreisposition) and (SalesLine.Artikelart <> '9') and
                        (SalesLine.Artikeltyp <> SalesLine.Artikeltyp::Fremdleistung)
                    then begin
                        //START B38°.2 ---------------------------------
                        //VALIDATE("VK-Rabatt1",SalesHeader."GU-Rabatt für Austauschartikel");
                        Validate("VK-Rabatt1", lo_cu_PreisfindungKundeArtikel.fnk_GetMehrMinderExchangeDisc(SalesHeader, SalesLine));
                        //STOP  B38°.2 ---------------------------------
                    end else
                        if (SalesLine.Positionsart = SalesLine.Positionsart::"gelöscht mit Aufpreisposition")
                         and (SalesLine.Artikelart <> '9') and (SalesLine.Artikeltyp <> SalesLine.Artikeltyp::Fremdleistung)
               then begin
                            //START B38°.2 ---------------------------------
                            //VALIDATE("VK-Rabatt1",SalesHeader."GU-Rabatt für Standardartikel");
                            Validate("VK-Rabatt1", lo_cu_PreisfindungKundeArtikel.fnk_GetMehrMinderStandardDisc(SalesHeader, SalesLine));
                            //STOP  B38°.2 ---------------------------------
                        end else begin
                            Validate("VK-Rabatt1", 0);
                        end;

                    Validate("VK-Rabatt2", 0);

                    if Artikeltyp = Artikeltyp::Setkomponente then
                        "Unit Price" := 0;

                end else begin
                    //STOP-A65°----------------------------

                    //START Axx° ---------------------------------
                    if Item."Div.Artikel" then begin
                        "Preis-KZ" := "Preis-KZ"::Brutto;
                    end else begin
                        if not "Allow Line Disc." then begin
                            "Line Discount %" := 0;
                            "Preis-KZ" := "Preis-KZ"::Netto;
                            Clear("VK-Rabatt1");
                            Clear("VK-Rabatt2");
                            Clear("VK-Rabatt3");
                        end else begin
                            "Preis-KZ" := "Preis-KZ"::Brutto;   //A22°.6
                        end;
                    end;
                    //STOP  Axx° ---------------------------------

                end;   // A65°

                //START Axx° ---------------------------------
                case TempSalesPrice."Sales Type" of
                    TempSalesPrice."Sales Type"::Customer:
                        SalesLine.Preisherkunft := SalesLine.Preisherkunft::Kundenindividuell;
                    TempSalesPrice."Sales Type"::"Customer Price Group":
                        begin
                            if SalesHeader."Sell-to Customer No." <> '' then begin
                                lo_re_Cust.Get(SalesHeader."Sell-to Customer No.");
                            end;
                            //START-A65°-----------------------
                            //IF (TempSalesPrice."Sales Code" = lo_re_Cust."Customer Price Group") THEN BEGIN
                            if (TempSalesPrice."Sales Code" = lo_re_Cust."Customer Price Group") or
                                (SalesHeader.Angebotsart in [SalesHeader.Angebotsart::"GU-Vorlage", SalesHeader.Angebotsart::"GU-Angebot"])
                            then begin
                                //STOP-A65°-----------------------
                                SalesLine.Preisherkunft := SalesLine.Preisherkunft::Preisliste;
                            end else begin
                                SalesLine.Preisherkunft := SalesLine.Preisherkunft::Nettopreisliste;
                            end;
                        end;
                end;
                //STOP  Axx° ---------------------------------
            end;

        end;
    end;

    local procedure fnk_OnAfterFindSalesPrice(var FromSalesPrice: Record "Sales Price"; var ToSalesPrice: Record "Sales Price"; CustNo: Code[20])
    var
        lo_re_Cust: Record Customer;
        lo_bo_Skip: Boolean;
    begin
        //C27°
        with FromSalesPrice do begin
            //START Axx° ---------------------------------
            if lo_re_Cust.Get(CustNo) then;
            if lo_re_Cust.Rabattleiste <> '' then begin
                //Prüfen ob in ToSalesPrice schon Einträge mit diesem SalesCode sind => Preisliste ist die gleiche => nix machen sonst Fehler
                ToSalesPrice.SetRange("Sales Type", "Sales Type"::"Customer Price Group");
                ToSalesPrice.SetRange("Sales Code", lo_re_Cust.Rabattleiste);
                if not ToSalesPrice.IsEmpty then begin
                    lo_bo_Skip := true;
                end;
                ToSalesPrice.SetRange("Sales Type");
                ToSalesPrice.SetRange("Sales Code");
                if not lo_bo_Skip then begin
                    SetRange("Sales Type", "Sales Type"::"Customer Price Group");
                    SetRange("Sales Code", lo_re_Cust.Rabattleiste);
                    CopySalesPriceToSalesPrice(FromSalesPrice, ToSalesPrice);
                end;
            end;
            //Achtung falls mal ausgelagert wird: bo_ConvertPrice muss während CopySalesPriceToSalesPrice für Nettopreise(=Rabattleiste)
            // auch TRUE sein wenn es in FindSalesPrice gesetzt wurde!
            // bzw. braucht es diese Variable überhaupt oder kann sie immer TRUE sein? TODO: Prüfen
            Clear(bo_ConvertPrice);
            //STOP  Axx° ---------------------------------
        end;
    end;
}

