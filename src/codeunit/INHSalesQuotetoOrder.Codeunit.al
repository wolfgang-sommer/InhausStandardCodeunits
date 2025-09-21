codeunit 50138 INHSalesQuoteToOrder
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // -------------------------------------------------------------
    // Axx°          RBI  28.07.08  Anpassungen in die CU übernommen
    //               SSC  24.01.25  Zlg.-Bedingungscode übernehmen (=Standard)
    // Axx°.1        SSC  17.11.22  Gesperrte Artikel umwandeln erlauben
    // Axx°.2        SSC  20.06.25  Fremdleistungen nie in Auftrag übernehmen, nicht nur bei GU
    // A30°.2        SSC  11.07.12  Meldung wenn Artikel mit Ersatzartikeln eingefügt wurden
    // A33°          RBI  28.07.08  Kalkulationsverwaltung
    // A65°          MBA  13.08.09  Ausgetauschte Positionen und Fremdleistungen vom Angebot nicht in Auftrag übernehmen
    // A65°.1        RBI  27.01.10  Textpositionen von Fremdleistungen vom Angebot nicht in Auftrag übernehmen.
    // A65°.2        SSC  11.01.12  Dem Auftrag bei Umwandlung Flag mitgeben wenn von Basis GU
    // A65°.4        SSC  01.07.15  Beim umwandeln von GU-Angeboten zuerst mit dem alten Datum rechnen da Preise neu gezogen werden durchs
    //                              Validate auf die Menge
    // A92°          RBI  27.01.10  Bilddatenbank: Image-Felder kopieren.
    // B17°.1        SSC  23.08.13  Gruppenpreise nicht in Auftrag übernehmen
    // B17°.5        SSC  14.11.23  Für MB/SST normal übernehmen
    // B41°.1        SSC  03.07.13  Schnäppchenshop
    // B44°          SSC  25.10.11  Variantenartikel
    // C01°          SSC  20.03.17  EP Vertrieb bei Div übernehmen bei Umwandlung Angebot in Auftrag
    // C09°          SSC  04.02.15  Währungsnachlass
    // C27°          SSC  29.08.17  Events, Hooks

    TableNo = "Sales Header";

    trigger OnRun()
    var
        Cust: Record Customer;
        SalesCommentLine: Record "Sales Comment Line";
        ApprovalsMgmt: Codeunit "Approvals Mgmt.";
        ArchiveManagement: Codeunit ArchiveManagement;
        SalesCalcDiscountByType: Codeunit "Sales - Calc Discount By Type";
        RecordLinkManagement: Codeunit "Record Link Management";
        ShouldRedistributeInvoiceAmount: Boolean;
        IsHandled: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_re_BillToCust: Record Customer;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_te_ItemsWithSubs: Text[1024];
    begin
        OnBeforeOnRun(Rec);

        TestField("Document Type", "Document Type"::Quote);
        ShouldRedistributeInvoiceAmount := SalesCalcDiscountByType.ShouldRedistributeInvoiceDiscountAmount(Rec);

        OnCheckSalesPostRestrictions;

        lo_cu_SalesMgt.fnk_Cu86_OnBeforeSalesQuoteToOrder(Rec);   //C27°

        bo_GUAngebot := (Angebotsart <> Angebotsart::" ");   //A65°

        Cust.Get("Sell-to Customer No.");
        Cust.CheckBlockedCustOnDocs(Cust, "Document Type"::Order, true, false);
        if "Sell-to Customer No." <> "Bill-to Customer No." then begin
            Cust.Get("Bill-to Customer No.");
            Cust.CheckBlockedCustOnDocs(Cust, "Document Type"::Order, true, false);
        end;
        CalcFields("Amount Including VAT", "Work Description");

        ValidateSalesPersonOnSalesHeader(Rec, true, false);

        //Axx°.1:CheckForBlockedLines;

        CheckInProgressOpportunities(Rec);

        CreateSalesHeader(Rec, Cust."Prepayment %");

        TransferQuoteToOrderLines(SalesQuoteLine, Rec, SalesOrderLine, SalesOrderHeader, Cust);
        OnAfterInsertAllSalesOrderLines(SalesOrderLine, Rec);

        SalesSetup.Get;
        case SalesSetup."Archive Quotes" of
            SalesSetup."Archive Quotes"::Always:
                ArchiveManagement.ArchSalesDocumentNoConfirm(Rec);
            SalesSetup."Archive Quotes"::Question:
                ArchiveManagement.ArchiveSalesDocument(Rec);
        end;

        if SalesSetup."Default Posting Date" = SalesSetup."Default Posting Date"::"No Date" then begin
            SalesOrderHeader."Posting Date" := 0D;
            SalesOrderHeader.Modify;
        end;

        //START A65°.4 ---------------------------------
        if bo_GUAngebot then begin
            SalesOrderHeader.Validate("Order Date", "Order Date");
            SalesOrderHeader.Modify;
        end;
        //STOP  A65°.4 ---------------------------------

        SalesCommentLine.CopyComments("Document Type", SalesOrderHeader."Document Type", "No.", SalesOrderHeader."No.");
        RecordLinkManagement.CopyLinks(Rec, SalesOrderHeader);

        AssignItemCharges("Document Type", "No.", SalesOrderHeader."Document Type", SalesOrderHeader."No.");

        MoveWonLostOpportunites(Rec, SalesOrderHeader);

        ApprovalsMgmt.CopyApprovalEntryQuoteToOrder(RecordId, SalesOrderHeader."No.", SalesOrderHeader.RecordId);

        IsHandled := false;
        OnBeforeDeleteSalesQuote(Rec, SalesOrderHeader, IsHandled);
        if not IsHandled then begin
            ApprovalsMgmt.DeleteApprovalEntries(RecordId);
            DeleteLinks;
            Delete;
            SalesQuoteLine.DeleteAll;
        end;

        lo_cu_SalesMgt.fnk_Cu86_OnAfterSalesQuoteToOrder(Rec, SalesOrderHeader);   //C27°

        if not ShouldRedistributeInvoiceAmount then
            SalesCalcDiscountByType.ResetRecalculateInvoiceDisc(SalesOrderHeader);

        OnAfterOnRun(Rec, SalesOrderHeader);
        //START A30°.2 ---------------------------------
        re_ItemWithSubstitutionTmp.Reset;
        if re_ItemWithSubstitutionTmp.FindSet(false, false) then begin
            repeat
                lo_te_ItemsWithSubs += re_ItemWithSubstitutionTmp."Item No." + ',';
            until re_ItemWithSubstitutionTmp.Next = 0;
            Message(TextItemSubExists2, lo_te_ItemsWithSubs);
        end;
        //STOP  A30°.2 ---------------------------------
    end;

    var
        Text000: Label 'An open %1 is linked to this %2. The %1 has to be closed before the %2 can be converted to an %3. Do you want to close the %1 now and continue the conversion?', Comment = 'An open Opportunity is linked to this Quote. The Opportunity has to be closed before the Quote can be converted to an Order. Do you want to close the Opportunity now and continue the conversion?';
        Text001: Label 'An open %1 is still linked to this %2. The conversion to an %3 was aborted.', Comment = 'An open Opportunity is still linked to this Quote. The conversion to an Order was aborted.';
        SalesQuoteLine: Record "Sales Line";
        SalesOrderHeader: Record "Sales Header";
        SalesOrderLine: Record "Sales Line";
        SalesSetup: Record "Sales & Receivables Setup";
        "+++VAR_INHAUS+++": Boolean;
        re_ItemWithSubstitutionTmp: Record "Inventory Buffer" temporary;
        bo_GUAngebot: Boolean;
        "+++TE_INHAUS+++": ;
        TextItemTypeChange: Label 'ACHTUNG:\Artikel %1 ist von Artikelart %2 auf %3 umgestellt worden! Bitte prüfen!\%4';
        TextItemSubExists: Label '\Es sind Ersatzartikel vorhanden!';
        TextItemSubExists2: Label 'Achtung es wurden Artikel mit Ersatzartikel eingefügt bitte prüfen.\%1';

    local procedure CreateSalesHeader(SalesHeader: Record "Sales Header"; PrepmtPercent: Decimal)
    begin
        OnBeforeCreateSalesHeader(SalesHeader);

        with SalesHeader do begin
            SalesOrderHeader := SalesHeader;
            SalesOrderHeader."Document Type" := SalesOrderHeader."Document Type"::Order;

            SalesOrderHeader."No. Printed" := 0;
            SalesOrderHeader.Status := SalesOrderHeader.Status::Open;
            SalesOrderHeader."No." := '';
            SalesOrderHeader."Quote No." := "No.";
            SalesOrderLine.LockTable;
            OnBeforeInsertSalesOrderHeader(SalesOrderHeader, SalesHeader);
            SalesOrderHeader.Insert(true);

            SalesOrderHeader."Order Date" := "Order Date";
            if "Posting Date" <> 0D then
                SalesOrderHeader."Posting Date" := "Posting Date";

            SalesOrderHeader.InitFromSalesHeader(SalesHeader);
            SalesOrderHeader."Outbound Whse. Handling Time" := "Outbound Whse. Handling Time";
            SalesOrderHeader.Reserve := Reserve;

            SalesOrderHeader."Prepayment %" := PrepmtPercent;
            if SalesOrderHeader."Posting Date" = 0D then
                SalesOrderHeader."Posting Date" := WorkDate;

            CalcFields("Work Description");
            SalesOrderHeader."Work Description" := "Work Description";

            //START Axx° ---------------------------------
            SalesOrderHeader."Posting Date" := WorkDate;
            //START A65°.4 ---------------------------------
            if bo_GUAngebot then begin
                SalesOrderHeader."Order Date" := "Order Date";
            end else
                //STOP  A65°.4 ---------------------------------
                SalesOrderHeader."Order Date" := WorkDate;
            SalesOrderHeader."Document Date" := WorkDate;
            SalesOrderHeader."Promised Delivery Date" := "Promised Delivery Date";
            //lo_re_BillToCustRecordCustomer
            //IF lo_re_BillToCust.GET("Bill-to Customer No.") THEN BEGIN
            //  IF lo_re_BillToCust."Payment Terms Code" <> SalesOrderHeader."Payment Terms Code" THEN BEGIN
            //    SalesOrderHeader.VALIDATE("Payment Terms Code",lo_re_BillToCust."Payment Terms Code");
            //  END;
            //END;
            //STOP  Axx° ---------------------------------
            //START A65° ---------------------------------
            Clear(SalesOrderHeader.Angebotsart);
            Clear(SalesOrderHeader."GU-Rabatt für Standardartikel");
            Clear(SalesOrderHeader."GU-Rabatt für Austauschartikel");
            //STOP  A65° ---------------------------------
            SalesOrderHeader."Currency Discount Date" := "Currency Discount Date";   //C09°

            OnBeforeModifySalesOrderHeader(SalesOrderHeader, SalesHeader);
            SalesOrderHeader.Modify;
        end;
    end;

    local procedure AssignItemCharges(FromDocType: Option; FromDocNo: Code[20]; ToDocType: Option; ToDocNo: Code[20])
    var
        ItemChargeAssgntSales: Record "Item Charge Assignment (Sales)";
    begin
        ItemChargeAssgntSales.Reset;
        ItemChargeAssgntSales.SetRange("Document Type", FromDocType);
        ItemChargeAssgntSales.SetRange("Document No.", FromDocNo);
        while ItemChargeAssgntSales.FindFirst do begin
            ItemChargeAssgntSales.Delete;
            ItemChargeAssgntSales."Document Type" := SalesOrderHeader."Document Type";
            ItemChargeAssgntSales."Document No." := SalesOrderHeader."No.";
            if not (ItemChargeAssgntSales."Applies-to Doc. Type" in
                    [ItemChargeAssgntSales."Applies-to Doc. Type"::Shipment,
                     ItemChargeAssgntSales."Applies-to Doc. Type"::"Return Receipt"])
            then begin
                ItemChargeAssgntSales."Applies-to Doc. Type" := ToDocType;
                ItemChargeAssgntSales."Applies-to Doc. No." := ToDocNo;
            end;
            ItemChargeAssgntSales.Insert;
        end;
    end;

    procedure GetSalesOrderHeader(var SalesHeader2: Record "Sales Header")
    begin
        SalesHeader2 := SalesOrderHeader;
    end;

    procedure SetHideValidationDialog(NewHideValidationDialog: Boolean)
    begin
        if NewHideValidationDialog then
            exit;
    end;

    local procedure CheckInProgressOpportunities(var SalesHeader: Record "Sales Header")
    var
        Opp: Record Opportunity;
        TempOpportunityEntry: Record "Opportunity Entry" temporary;
        ConfirmManagement: Codeunit "Confirm Management";
    begin
        Opp.Reset;
        Opp.SetCurrentKey("Sales Document Type", "Sales Document No.");
        Opp.SetRange("Sales Document Type", Opp."Sales Document Type"::Quote);
        Opp.SetRange("Sales Document No.", SalesHeader."No.");
        Opp.SetRange(Status, Opp.Status::"In Progress");
        if Opp.FindFirst then begin
            if not ConfirmManagement.GetResponse
                 StrSubstNo(
                   Text000, Opp.TableCaption, Opp."Sales Document Type"::Quote,
                   Opp."Sales Document Type"::Order), true)
            then
                Error('');
            TempOpportunityEntry.DeleteAll;
            TempOpportunityEntry.Init;
            TempOpportunityEntry.Validate("Opportunity No.", Opp."No.");
            TempOpportunityEntry."Sales Cycle Code" := Opp."Sales Cycle Code";
            TempOpportunityEntry."Contact No." := Opp."Contact No.";
            TempOpportunityEntry."Contact Company No." := Opp."Contact Company No.";
            TempOpportunityEntry."Salesperson Code" := Opp."Salesperson Code";
            TempOpportunityEntry."Campaign No." := Opp."Campaign No.";
            TempOpportunityEntry."Action Taken" := TempOpportunityEntry."Action Taken"::Won;
            TempOpportunityEntry."Calcd. Current Value (LCY)" := TempOpportunityEntry.GetSalesDocValue(SalesHeader);
            TempOpportunityEntry."Cancel Old To Do" := true;
            TempOpportunityEntry."Wizard Step" := 1;
            TempOpportunityEntry.Insert;
            TempOpportunityEntry.SetRange("Action Taken", TempOpportunityEntry."Action Taken"::Won);
            PAGE.RunModal(PAGE::"Close Opportunity", TempOpportunityEntry);
            Opp.Reset;
            Opp.SetCurrentKey("Sales Document Type", "Sales Document No.");
            Opp.SetRange("Sales Document Type", Opp."Sales Document Type"::Quote);
            Opp.SetRange("Sales Document No.", SalesHeader."No.");
            Opp.SetRange(Status, Opp.Status::"In Progress");
            if Opp.FindFirst then
                Error(Text001, Opp.TableCaption, Opp."Sales Document Type"::Quote, Opp."Sales Document Type"::Order);
            Commit;
            SalesHeader.Get(SalesHeader."Document Type", SalesHeader."No.");
        end;
    end;

    local procedure MoveWonLostOpportunites(var SalesQuoteHeader: Record "Sales Header"; var SalesOrderHeader: Record "Sales Header")
    var
        Opp: Record Opportunity;
        OpportunityEntry: Record "Opportunity Entry";
    begin
        Opp.Reset;
        Opp.SetCurrentKey("Sales Document Type", "Sales Document No.");
        Opp.SetRange("Sales Document Type", Opp."Sales Document Type"::Quote);
        Opp.SetRange("Sales Document No.", SalesQuoteHeader."No.");
        if Opp.FindFirst then
            if Opp.Status = Opp.Status::Won then begin
                Opp."Sales Document Type" := Opp."Sales Document Type"::Order;
                Opp."Sales Document No." := SalesOrderHeader."No.";
                Opp.Modify;
                OpportunityEntry.Reset;
                OpportunityEntry.SetCurrentKey(Active, "Opportunity No.");
                OpportunityEntry.SetRange(Active, true);
                OpportunityEntry.SetRange("Opportunity No.", Opp."No.");
                if OpportunityEntry.FindFirst then begin
                    OpportunityEntry."Calcd. Current Value (LCY)" := OpportunityEntry.GetSalesDocValue(SalesOrderHeader);
                    OpportunityEntry.Modify;
                end;
            end else
                if Opp.Status = Opp.Status::Lost then begin
                    Opp."Sales Document Type" := Opp."Sales Document Type"::" ";
                    Opp."Sales Document No." := '';
                    Opp.Modify;
                end;
    end;

    local procedure TransferQuoteToOrderLines(var SalesQuoteLine: Record "Sales Line"; var SalesQuoteHeader: Record "Sales Header"; var SalesOrderLine: Record "Sales Line"; var SalesOrderHeader: Record "Sales Header"; Customer: Record Customer)
    var
        ATOLink: Record "Assemble-to-Order Link";
        PrepmtMgt: Codeunit "Prepayment Mgt.";
        SalesLineReserve: Codeunit "Sales Line-Reserve";
        IsHandled: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_re_Item: Record Item;
        lo_re_ItemSubstitution: Record "Item Substitution";
        lo_re_SalesLine2: Record "Sales Line";
        lo_cu_ICMgt: Codeunit ICMgt;
        lo_cu_ItemMgt: Codeunit ItemMgt;
        lo_cu_CalcMgt: Codeunit CalcMgt;
        lo_cu_SalesLineMgt: Codeunit SalesLineMgt;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_cu_VariantMgt: Codeunit VariantMgt;
        lo_de_Available: Decimal;
        lo_de_Dummy: Decimal;
        lo_bo_CopyLine: Boolean;
    begin
        SalesQuoteLine.Reset;
        SalesQuoteLine.SetRange("Document Type", SalesQuoteHeader."Document Type");
        SalesQuoteLine.SetRange("Document No.", SalesQuoteHeader."No.");
        SalesQuoteLine.SetFilter(Auftragsnummer, '=%1', '');   //Axx°
        OnTransferQuoteToOrderLinesOnAfterSetFilters(SalesQuoteLine, SalesQuoteHeader);
        if SalesQuoteLine.FindSet then
            repeat
                IsHandled := false;
                OnBeforeTransferQuoteLineToOrderLineLoop(SalesQuoteLine, SalesQuoteHeader, SalesOrderHeader, IsHandled);
                if not IsHandled then begin
                    SalesOrderLine := SalesQuoteLine;
                    //START Axx° ---------------------------------
                    lo_bo_CopyLine := true;
                    if (SalesQuoteLine."No." <> '') and (SalesQuoteLine.Type = SalesQuoteLine.Type::Item) then begin
                        lo_re_Item.Get(SalesQuoteLine."No.");
                    end;

                    //START-A65°-----------------------------
                    //START Axx°.2 ---------------------------------
                    //IF (lo_bo_CopyLine) AND (bo_GUAngebot) AND (SalesQuoteLine."No." <> '') AND
                    if (lo_bo_CopyLine) and (SalesQuoteLine."No." <> '') and
                       //STOP  Axx°.2 ---------------------------------
                       (SalesQuoteLine.Type = SalesQuoteLine.Type::Item)
                    then begin
                        if lo_re_Item.Artikeltyp = lo_re_Item.Artikeltyp::Fremdleistung then
                            lo_bo_CopyLine := false;
                    end;

                    //START Axx°.2 ---------------------------------
                    if (lo_bo_CopyLine) and (SalesQuoteLine.Type = SalesQuoteLine.Type::" ") and
                        (SalesQuoteLine.Quantity = 0) and (SalesQuoteLine."Attached to Line No." <> 0)
                    then begin
                        lo_re_SalesLine2.Get(SalesQuoteLine."Document Type", SalesQuoteLine."Document No.", SalesQuoteLine."Attached to Line No.");
                        if lo_re_SalesLine2.Artikeltyp = lo_re_SalesLine2.Artikeltyp::Fremdleistung then begin
                            lo_bo_CopyLine := false;
                        end;
                    end;
                    //STOP  Axx°.2 ---------------------------------

                    if (lo_bo_CopyLine) and (bo_GUAngebot) and (SalesQuoteLine."No." <> '') and
                       (SalesQuoteLine.Type = SalesQuoteLine.Type::Item) and (SalesQuoteLine.Quantity = 0)
                    then begin
                        lo_bo_CopyLine := false;
                    end else begin
                        if (lo_bo_CopyLine) and (bo_GUAngebot) and (SalesQuoteLine.Type = SalesQuoteLine.Type::" ") and
                           (SalesQuoteLine.Quantity = 0) and (SalesQuoteLine."Attached to Line No." <> 0)
                        then begin
                            //Prüfen ob die aktuelle Textzeile zu einem ausgetauschten Artikel gehört
                            lo_re_SalesLine2.Get(SalesQuoteLine."Document Type", SalesQuoteLine."Document No.", SalesQuoteLine."Attached to Line No.");
                            if (lo_re_SalesLine2.Type = lo_re_SalesLine2.Type::Item) and (lo_re_SalesLine2.Quantity = 0) then
                                lo_bo_CopyLine := false;

                            //START Axx°.2 ---------------------------------
                            //Prüfung jetzt schon weiter oben, doppelter Code
                            ////START A65°.1 ----------------------------------------------------------------
                            //IF lo_re_SalesLine2.Artikeltyp = lo_re_SalesLine2.Artikeltyp::Fremdleistung THEN
                            //  lo_bo_CopyLine := FALSE;
                            ////STOP A65°.1 ----------------------------------------------------------------
                            //STOP  Axx°.2 ---------------------------------

                        end;
                    end;
                    //STOP-A65°-----------------------------

                    //START B17°.1 ---------------------------------
                    if not lo_cu_SalesMgt.fnk_DoCopyGruppenpreisQuoteToOrder(SalesQuoteLine) then begin   //B17°.5
                        if lo_bo_CopyLine then begin
                            if SalesQuoteLine.Gruppenpreis > 0 then begin
                                lo_bo_CopyLine := false;
                            end else
                                if SalesQuoteLine.Gruppenpreis < 0 then begin
                                    SalesQuoteLine.Gruppenpreis := 0;
                                    SalesOrderLine.Gruppenpreis := 0;
                                end else
                                    if SalesQuoteLine.Description = lo_cu_SalesLineMgt.fnk_GetTextGroupPriceMark then begin
                                        lo_bo_CopyLine := false;
                                    end;
                        end;
                    end;   //B17°.5
                           //STOP  B17°.1 ---------------------------------

                    if lo_bo_CopyLine then begin
                        //STOP  Axx° ---------------------------------
                        SalesOrderLine."Document Type" := SalesOrderHeader."Document Type";
                        SalesOrderLine."Document No." := SalesOrderHeader."No.";
                        SalesOrderLine."Shortcut Dimension 1 Code" := SalesQuoteLine."Shortcut Dimension 1 Code";
                        SalesOrderLine."Shortcut Dimension 2 Code" := SalesQuoteLine."Shortcut Dimension 2 Code";
                        SalesOrderLine."Dimension Set ID" := SalesQuoteLine."Dimension Set ID";
                        SalesOrderLine."Transaction Type" := SalesOrderHeader."Transaction Type";
                        if Customer."Prepayment %" <> 0 then
                            SalesOrderLine."Prepayment %" := Customer."Prepayment %";
                        PrepmtMgt.SetSalesPrepaymentPct(SalesOrderLine, SalesOrderHeader."Posting Date");
                        SalesOrderLine.Validate("Prepayment %");
                        if SalesOrderLine."No." <> '' then
                            SalesOrderLine.DefaultDeferralCode;
                        //START-A65°-----------------------------
                        Clear(SalesOrderLine."Special Order Purch. Line No.");
                        if (bo_GUAngebot) and (SalesQuoteLine.Type = SalesQuoteLine.Type::Item) and (SalesQuoteLine."No." <> '') then begin
                            SalesOrderLine.fnk_SetFromGUQuote(true);   // A65°.2
                            SalesOrderLine.Validate(Quantity);
                        end;
                        //STOP-A65°-----------------------------
                        //START Axx° ---------------------------------
                        SalesOrderLine.Angebotsnummer := SalesQuoteLine."Document No.";
                        SalesOrderLine."Angebotszeilennr." := SalesQuoteLine."Line No.";
                        if SalesQuoteLine.Type = SalesQuoteLine.Type::Item then begin
                            SalesOrderLine.Validate("Kreditornr.", SalesQuoteLine."Kreditornr.");
                            lo_cu_ItemMgt.FNK_CheckSchnaeppchenShop(SalesOrderLine."No.");   //B41°.1
                            SalesOrderLine.Artikelart := lo_re_Item."Item Type";
                        end;

                        if (lo_re_Item."Item Type" <> SalesQuoteLine.Artikelart) and (SalesQuoteLine."No." <> '') and
                           (SalesQuoteLine.Quantity <> 0) and (SalesQuoteLine.Type = SalesQuoteLine.Type::Item) and
                           (lo_re_Item."Item Type" in ['6', '8'])
                        then begin
                            lo_cu_ICMgt.FNK_GetItemInventoryData(SalesOrderLine."Location Code", lo_re_Item."No.", '',
                                                             lo_de_Dummy, lo_de_Available, lo_de_Dummy, lo_de_Dummy,
                                                             lo_de_Dummy, lo_de_Dummy, lo_de_Dummy);
                            if lo_de_Available <= 0 then begin
                                lo_re_ItemSubstitution.Reset;
                                lo_re_ItemSubstitution.SetRange(Type, lo_re_ItemSubstitution.Type::Item);
                                lo_re_ItemSubstitution.SetRange("No.", lo_re_Item."No.");
                                if lo_re_ItemSubstitution.FindFirst then
                                    Error(TextItemTypeChange, lo_re_Item."No.", SalesQuoteLine.Artikelart, lo_re_Item."Item Type", TextItemSubExists)
                                else
                                    Error(TextItemTypeChange, lo_re_Item."No.", SalesQuoteLine.Artikelart, lo_re_Item."Item Type", '');
                            end;
                        end;
                        //START A92° ---------------------------------
                        SalesOrderLine."Explosionszeichnung Drucken" := SalesQuoteLine."Explosionszeichnung Drucken";
                        SalesOrderLine."Maßskizze Drucken" := SalesQuoteLine."Maßskizze Drucken";
                        SalesOrderLine."Katalogbild Drucken" := SalesQuoteLine."Katalogbild Drucken";
                        SalesOrderLine."PDF-Datei Drucken" := SalesQuoteLine."PDF-Datei Drucken";
                        //STOP  A92° ---------------------------------
                        if (SalesOrderHeader.IC_Typ = SalesOrderHeader.IC_Typ::Auftrag) then begin
                            SalesOrderLine.IC_Typ := SalesOrderLine.IC_Typ::Auftrag;
                            SalesOrderLine.IC_Mandant := CompanyName;
                            //START B44° ---------------------------------
                            // nötig, um später korrekte Chargennr. zu erzeugen
                            SalesOrderLine.IC_Auftrag := SalesOrderLine."Document No.";
                            SalesOrderLine.IC_AuftragZeile := SalesOrderLine."Line No.";
                            //STOP  B44° ---------------------------------
                            SalesOrderLine."Location Code" := '1';
                            if (SalesOrderLine.Type = SalesOrderLine.Type::Item) and (SalesOrderLine."No." <> '') then begin
                                SalesOrderLine.Validate(Quantity);
                                SalesOrderLine."Preis-KZ" := SalesQuoteLine."Preis-KZ";
                                SalesOrderLine.Validate("Unit Price", SalesQuoteLine."Unit Price");
                                SalesOrderLine.Validate("VK-Rabatt1", SalesQuoteLine."VK-Rabatt1");
                                SalesOrderLine.Validate("VK-Rabatt2", SalesQuoteLine."VK-Rabatt2");
                                SalesOrderLine.Validate("VK-Rabatt3", SalesQuoteLine."VK-Rabatt3");
                            end;
                        end;
                        //STOP  Axx° ---------------------------------
                        //START C01° ---------------------------------
                        if SalesQuoteLine."Div. Artikel" and (SalesQuoteLine."No." <> '') then begin
                            SalesOrderLine."Unit Cost Sales 1" := SalesQuoteLine."Unit Cost Sales 1";
                            SalesOrderLine."Unit Cost Sales 2" := SalesQuoteLine."Unit Cost Sales 2";
                            SalesOrderLine."Unit Cost Sales 3" := SalesQuoteLine."Unit Cost Sales 3";
                        end;
                        //STOP  C01° ---------------------------------
                        SalesOrderLine.Validate("Creation Datetime", CurrentDateTime);   //Axx°

                        OnBeforeInsertSalesOrderLine(SalesOrderLine, SalesOrderHeader, SalesQuoteLine, SalesQuoteHeader);
                        SalesOrderLine.Insert;
                        OnAfterInsertSalesOrderLine(SalesOrderLine, SalesOrderHeader, SalesQuoteLine, SalesQuoteHeader);
                        ATOLink.MakeAsmOrderLinkedToSalesOrderLine(SalesQuoteLine, SalesOrderLine);
                        SalesLineReserve.TransferSaleLineToSalesLine(
                          SalesQuoteLine, SalesOrderLine, SalesQuoteLine."Outstanding Qty. (Base)");
                        SalesLineReserve.VerifyQuantity(SalesOrderLine, SalesQuoteLine);
                        if SalesOrderLine.Reserve = SalesOrderLine.Reserve::Always then
                            SalesOrderLine.AutoReserve;
                        lo_cu_CalcMgt.FNK_KalkulationVonVKBelegZuVKB(SalesQuoteLine, SalesOrderLine);   //A33°
                        lo_cu_VariantMgt.fnk_CopySalesDLV(SalesQuoteLine, SalesOrderLine);   // B44°
                                                                                             //START A30°.2 ---------------------------------
                        lo_re_ItemSubstitution.Reset;
                        lo_re_ItemSubstitution.SetRange(Type, lo_re_ItemSubstitution.Type::Item);
                        lo_re_ItemSubstitution.SetRange("No.", lo_re_Item."No.");
                        if lo_re_ItemSubstitution.FindFirst then begin
                            re_ItemWithSubstitutionTmp."Item No." := lo_re_Item."No.";
                            if not re_ItemWithSubstitutionTmp.Insert then
                                re_ItemWithSubstitutionTmp.Modify;
                        end;
                        //STOP  A30°.2 ---------------------------------

                    end;   //Axx°
                end;
            until SalesQuoteLine.Next = 0;
        SalesQuoteLine.SetRange(Auftragsnummer);   //Axx°
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateSalesHeader(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeDeleteSalesQuote(var QuoteSalesHeader: Record "Sales Header"; var OrderSalesHeader: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertSalesOrderHeader(var SalesOrderHeader: Record "Sales Header"; SalesQuoteHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeModifySalesOrderHeader(var SalesOrderHeader: Record "Sales Header"; SalesQuoteHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInsertSalesOrderLine(var SalesOrderLine: Record "Sales Line"; SalesOrderHeader: Record "Sales Header"; SalesQuoteLine: Record "Sales Line"; SalesQuoteHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInsertAllSalesOrderLines(var SalesOrderLine: Record "Sales Line"; SalesQuoteHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterOnRun(var SalesHeader: Record "Sales Header"; var SalesOrderHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeInsertSalesOrderLine(var SalesOrderLine: Record "Sales Line"; SalesOrderHeader: Record "Sales Header"; SalesQuoteLine: Record "Sales Line"; SalesQuoteHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeOnRun(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeTransferQuoteLineToOrderLineLoop(var SalesQuoteLine: Record "Sales Line"; var SalesQuoteHeader: Record "Sales Header"; var SalesOrderHeader: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnTransferQuoteToOrderLinesOnAfterSetFilters(var SalesQuoteLine: Record "Sales Line"; var SalesQuoteHeader: Record "Sales Header")
    begin
    end;
}

