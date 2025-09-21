codeunit 50168 INHArchiveManagement
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // A65°          RBI  21.06.11  Die GU-Felder bei Wiederherstellung übernehmen
    // B25°          SSC  25.08.11  CurrFieldNo nachbilden
    // B40°          JLE  03.02.09  Anpassungen übernommen
    // B40°.1        SSC  17.01.12  Zahlungsbed. neu ziehen bei Wiederherstellung
    // B40°.2        SSC  30.05.12  "Verk. an Deb.Nr." immer validieren, auch wenn Kontakt vorhanden (Beziehungen wurden gelöscht)
    //               SSC  26.11.18  Debitorenrabattgruppe muss die alte verwendet werden
    // B40°.3        SSC  29.08.13  IC_Typ nötig für Ermittlung des richtigen Lagerortes beim Insert(True)
    // B40°.6        SSC  27.08.14  Bei Angebot nicht in neue Nummer wiederherstellen sondern selbe verwenden; keine Validates
    // B40°.8        SSC  24.08.11  Setartikel Wiederherstellung (war A20°.2)
    // B40°.9        SSC  04.12.18  Nur Archivierung bei irgendeiner Änderung
    // B40°.10       SSC  21.07.23  Record Link führte zu Performance und Sperrproblemen, wird eh nicht verwendet
    // C01°          SSC  03.03.16  EP-Felder neu berechnen beim Wiederherstellen
    // C02°          SSC  29.04.15  "Job Task No." berücksichtigen, da in Archivzeile nicht im Standard -> andere Nr.
    // C27°          SSC  23.08.17  Events, Hooks
    // C51°          SSC  11.06.21  "Freigabe Bäderpark" nicht wiederherstellen
    // C73°          SSC  23.02.21  Nettoprojekt nicht wiederherstellen, da in Zukunft nicht mehr in Verwendung
    //               SSC  04.06.24  Wieder aktiv


    trigger OnRun()
    begin
    end;

    var
        Text001: Label 'Document %1 has been archived.';
        Text002: Label 'Do you want to Restore %1 %2 Version %3?';
        Text003: Label '%1 %2 has been restored.';
        Text004: Label 'Document restored from Version %1.';
        Text005: Label '%1 %2 has been partly posted.\Restore not possible.';
        Text006: Label 'Entries exist for on or more of the following:\  - %1\  - %2\  - %3.\Restoration of document will delete these entries.\Continue with restore?';
        Text007: Label 'Archive %1 no.: %2?';
        Text008: Label 'Item Tracking Line';
        ReleaseSalesDoc: Codeunit "Release Sales Document";
        Text009: Label 'Unposted %1 %2 does not exist anymore.\It is not possible to restore the %1.';
        DeferralUtilities: Codeunit "Deferral Utilities";
        RecordLinkManagement: Codeunit "Record Link Management";

    procedure AutoArchiveSalesDocument(var SalesHeader: Record "Sales Header")
    var
        SalesReceivablesSetup: Record "Sales & Receivables Setup";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeAutoArchiveSalesDocument(SalesHeader, IsHandled);
        if IsHandled then
            exit;

        SalesReceivablesSetup.Get;

        with SalesHeader do
            case "Document Type" of
                "Document Type"::Quote:
                    case SalesReceivablesSetup."Archive Quotes" of
                        SalesReceivablesSetup."Archive Quotes"::Always:
                            ArchSalesDocumentNoConfirm(SalesHeader);
                        SalesReceivablesSetup."Archive Quotes"::Question:
                            ArchiveSalesDocument(SalesHeader);
                    end;
                "Document Type"::Order:
                    if SalesReceivablesSetup."Archive Orders" then begin
                        PrepareDeferralsForSalesOrder(SalesHeader);
                        ArchSalesDocumentNoConfirm(SalesHeader);
                    end;
                "Document Type"::"Blanket Order":
                    if SalesReceivablesSetup."Archive Blanket Orders" then
                        ArchSalesDocumentNoConfirm(SalesHeader);
                "Document Type"::"Return Order":
                    if SalesReceivablesSetup."Archive Return Orders" then
                        ArchSalesDocumentNoConfirm(SalesHeader);
            end;

        OnAfterAutoArchiveSalesDocument(SalesHeader);
    end;

    procedure AutoArchivePurchDocument(var PurchaseHeader: Record "Purchase Header")
    var
        PurchasesPayablesSetup: Record "Purchases & Payables Setup";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeAutoArchivePurchDocument(PurchaseHeader, IsHandled);
        if IsHandled then
            exit;

        PurchasesPayablesSetup.Get;

        with PurchaseHeader do
            case "Document Type" of
                "Document Type"::Quote:
                    case PurchasesPayablesSetup."Archive Quotes" of
                        PurchasesPayablesSetup."Archive Quotes"::Always:
                            ArchPurchDocumentNoConfirm(PurchaseHeader);
                        PurchasesPayablesSetup."Archive Quotes"::Question:
                            ArchivePurchDocument(PurchaseHeader);
                    end;
                "Document Type"::Order:
                    if PurchasesPayablesSetup."Archive Orders" then begin
                        PrepareDeferralsPurchaseOrder(PurchaseHeader);
                        ArchPurchDocumentNoConfirm(PurchaseHeader);
                    end;
                "Document Type"::"Blanket Order":
                    if PurchasesPayablesSetup."Archive Blanket Orders" then
                        ArchPurchDocumentNoConfirm(PurchaseHeader);
                "Document Type"::"Return Order":
                    if PurchasesPayablesSetup."Archive Return Orders" then
                        ArchPurchDocumentNoConfirm(PurchaseHeader);
            end;

        OnAfterAutoArchivePurchDocument(PurchaseHeader);
    end;

    procedure ArchiveSalesDocument(var SalesHeader: Record "Sales Header")
    var
        ConfirmManagement: Codeunit "Confirm Management";
    begin
        if ConfirmManagement.ConfirmProcess(
             StrSubstNo(Text007, SalesHeader."Document Type", SalesHeader."No."), true)
        then begin
            StoreSalesDocument(SalesHeader, false);
            Message(Text001, SalesHeader."No.");
        end;
    end;

    procedure ArchivePurchDocument(var PurchHeader: Record "Purchase Header")
    var
        ConfirmManagement: Codeunit "Confirm Management";
    begin
        if ConfirmManagement.ConfirmProcess(
             StrSubstNo(Text007, PurchHeader."Document Type", PurchHeader."No."), true)
        then begin
            StorePurchDocument(PurchHeader, false);
            Message(Text001, PurchHeader."No.");
        end;
    end;

    procedure StoreSalesDocument(var SalesHeader: Record "Sales Header"; InteractionExist: Boolean)
    var
        SalesLine: Record "Sales Line";
        SalesHeaderArchive: Record "Sales Header Archive";
        SalesLineArchive: Record "Sales Line Archive";
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_SalesMgt: Codeunit SalesMgt;
    begin
        SalesHeaderArchive.Init;
        SalesHeaderArchive.TransferFields(SalesHeader);
        SalesHeaderArchive."Archived By" := UserId;
        SalesHeaderArchive."Date Archived" := WorkDate;
        SalesHeaderArchive."Time Archived" := Time;
        SalesHeaderArchive."Version No." := GetNextVersionNo(
            DATABASE::"Sales Header", SalesHeader."Document Type", SalesHeader."No.", SalesHeader."Doc. No. Occurrence");
        SalesHeaderArchive."Interaction Exist" := InteractionExist;
        //B40°.10:RecordLinkManagement.CopyLinks(SalesHeader,SalesHeaderArchive);
        OnBeforeSalesHeaderArchiveInsert(SalesHeaderArchive, SalesHeader);
        SalesHeaderArchive.Insert;
        OnAfterSalesHeaderArchiveInsert(SalesHeaderArchive, SalesHeader);

        StoreSalesDocumentComments(
          SalesHeader."Document Type", SalesHeader."No.",
          SalesHeader."Doc. No. Occurrence", SalesHeaderArchive."Version No.");

        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        if SalesLine.FindSet then
            repeat
                with SalesLineArchive do begin
                    Init;
                    TransferFields(SalesLine);
                    "Doc. No. Occurrence" := SalesHeader."Doc. No. Occurrence";
                    "Version No." := SalesHeaderArchive."Version No.";
                    SalesLineArchive."Job Task No." := SalesLine."Job Task No.";   //C02°
                                                                                   //B40°.10:RecordLinkManagement.CopyLinks(SalesLine,SalesLineArchive);
                    OnBeforeSalesLineArchiveInsert(SalesLineArchive, SalesLine);
                    Insert;
                end;
                if SalesLine."Deferral Code" <> '' then
                    StoreDeferrals(DeferralUtilities.GetSalesDeferralDocType, SalesLine."Document Type",
                      SalesLine."Document No.", SalesLine."Line No.", SalesHeader."Doc. No. Occurrence", SalesHeaderArchive."Version No.");

                OnAfterStoreSalesLineArchive(SalesHeader, SalesLine, SalesHeaderArchive, SalesLineArchive);
            until SalesLine.Next = 0;

        OnAfterStoreSalesDocument(SalesHeader, SalesHeaderArchive);
        lo_cu_SalesMgt.fnk_Cu5063_OnAfterStoreSalesDocument(SalesHeader, SalesHeaderArchive);   //C27°
    end;

    procedure StorePurchDocument(var PurchHeader: Record "Purchase Header"; InteractionExist: Boolean)
    var
        PurchLine: Record "Purchase Line";
        PurchHeaderArchive: Record "Purchase Header Archive";
        PurchLineArchive: Record "Purchase Line Archive";
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_PurchMgt: Codeunit PurchaseMgt;
    begin
        PurchHeaderArchive.Init;
        PurchHeaderArchive.TransferFields(PurchHeader);
        PurchHeaderArchive."Archived By" := UserId;
        PurchHeaderArchive."Date Archived" := WorkDate;
        PurchHeaderArchive."Time Archived" := Time;
        PurchHeaderArchive."Version No." := GetNextVersionNo(
            DATABASE::"Purchase Header", PurchHeader."Document Type", PurchHeader."No.", PurchHeader."Doc. No. Occurrence");
        PurchHeaderArchive."Interaction Exist" := InteractionExist;
        //B40°.10:RecordLinkManagement.CopyLinks(PurchHeader,PurchHeaderArchive);
        OnBeforePurchHeaderArchiveInsert(PurchHeaderArchive, PurchHeader);
        PurchHeaderArchive.Insert;
        OnAfterPurchHeaderArchiveInsert(PurchHeaderArchive, PurchHeader);

        StorePurchDocumentComments(
          PurchHeader."Document Type", PurchHeader."No.",
          PurchHeader."Doc. No. Occurrence", PurchHeaderArchive."Version No.");

        PurchLine.SetRange("Document Type", PurchHeader."Document Type");
        PurchLine.SetRange("Document No.", PurchHeader."No.");
        if PurchLine.FindSet then
            repeat
                with PurchLineArchive do begin
                    Init;
                    TransferFields(PurchLine);
                    "Doc. No. Occurrence" := PurchHeader."Doc. No. Occurrence";
                    "Version No." := PurchHeaderArchive."Version No.";
                    //B40°.10:RecordLinkManagement.CopyLinks(PurchLine,PurchLineArchive);
                    OnBeforePurchLineArchiveInsert(PurchLineArchive, PurchLine);
                    Insert;
                end;
                if PurchLine."Deferral Code" <> '' then
                    StoreDeferrals(DeferralUtilities.GetPurchDeferralDocType, PurchLine."Document Type",
                      PurchLine."Document No.", PurchLine."Line No.", PurchHeader."Doc. No. Occurrence", PurchHeaderArchive."Version No.");

                OnAfterStorePurchLineArchive(PurchHeader, PurchLine, PurchHeaderArchive, PurchLineArchive);
            until PurchLine.Next = 0;

        OnAfterStorePurchDocument(PurchHeader, PurchHeaderArchive);
        lo_cu_PurchMgt.fnk_Cu5063_OnAfterStorePurchDocument(PurchHeader, PurchHeaderArchive);   //C27°
    end;

    procedure RestoreSalesDocument(var SalesHeaderArchive: Record "Sales Header Archive")
    var
        SalesHeader: Record "Sales Header";
        SalesShptHeader: Record "Sales Shipment Header";
        SalesInvHeader: Record "Sales Invoice Header";
        ReservEntry: Record "Reservation Entry";
        ItemChargeAssgntSales: Record "Item Charge Assignment (Sales)";
        ConfirmManagement: Codeunit "Confirm Management";
        ConfirmRequired: Boolean;
        RestoreDocument: Boolean;
        OldOpportunityNo: Code[20];
        IsHandled: Boolean;
        DoCheck: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_re_Cust: Record Customer;
        lo_re_Item: Record Item;
        lo_cu_OverallVariableMgt: Codeunit OverallVariableMgt;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_bo_SkipValidation: Boolean;
    begin
        OnBeforeRestoreSalesDocument(SalesHeaderArchive, IsHandled);
        if IsHandled then
            exit;

        lo_cu_SalesMgt.fnk_Cu5063_OnBeforeRestoreSalesDocument(SalesHeaderArchive);   //C27°
        if not SalesHeader.Get(SalesHeaderArchive."Document Type", SalesHeaderArchive."No.") then
            Error(Text009, SalesHeaderArchive."Document Type", SalesHeaderArchive."No.");

        SalesHeader.TestField(Status, SalesHeader.Status::Open);

        DoCheck := true;
        OnBeforeCheckIfDocumentIsPartiallyPosted(SalesHeaderArchive, DoCheck);

        if (SalesHeader."Document Type" = SalesHeader."Document Type"::Order) and DoCheck then begin
            SalesShptHeader.Reset;
            SalesShptHeader.SetCurrentKey("Order No.");
            SalesShptHeader.SetRange("Order No.", SalesHeader."No.");
            if not SalesShptHeader.IsEmpty then
                Error(Text005, SalesHeader."Document Type", SalesHeader."No.");
            SalesInvHeader.Reset;
            SalesInvHeader.SetCurrentKey("Order No.");
            SalesInvHeader.SetRange("Order No.", SalesHeader."No.");
            if not SalesInvHeader.IsEmpty then
                Error(Text005, SalesHeader."Document Type", SalesHeader."No.");
        end;

        ConfirmRequired := false;
        ReservEntry.Reset;
        ReservEntry.SetCurrentKey("Source ID", "Source Ref. No.", "Source Type", "Source Subtype");
        ReservEntry.SetRange("Source ID", SalesHeader."No.");
        ReservEntry.SetRange("Source Type", DATABASE::"Sales Line");
        ReservEntry.SetRange("Source Subtype", SalesHeader."Document Type");
        if ReservEntry.FindFirst then
            ConfirmRequired := true;

        ItemChargeAssgntSales.Reset;
        ItemChargeAssgntSales.SetRange("Document Type", SalesHeader."Document Type");
        ItemChargeAssgntSales.SetRange("Document No.", SalesHeader."No.");
        if ItemChargeAssgntSales.FindFirst then
            ConfirmRequired := true;

        RestoreDocument := false;
        if ConfirmRequired then begin
            if ConfirmManagement.ConfirmProcess(
                 StrSubstNo(
                   Text006, ReservEntry.TableCaption, ItemChargeAssgntSales.TableCaption, Text008), true)
            then
                RestoreDocument := true;
        end else
            if ConfirmManagement.ConfirmProcess(
                 StrSubstNo(
                   Text002, SalesHeaderArchive."Document Type",
                   SalesHeaderArchive."No.", SalesHeaderArchive."Version No."), true)
            then
                RestoreDocument := true;
        if RestoreDocument then begin
            SalesHeader.TestField("Doc. No. Occurrence", SalesHeaderArchive."Doc. No. Occurrence");
            SalesHeaderArchive.CalcFields("Work Description");
            if SalesHeader."Opportunity No." <> '' then begin
                OldOpportunityNo := SalesHeader."Opportunity No.";
                SalesHeader."Opportunity No." := '';
            end;
            OnRestoreDocumentOnBeforeDeleteSalesHeader(SalesHeader);
            SalesHeader.DeleteLinks;
            SalesHeader.Delete(true);
            OnRestoreDocumentOnAfterDeleteSalesHeader(SalesHeader);

            SalesHeader.Init;
            SalesHeader.SetHideValidationDialog(true);
            SalesHeader."Document Type" := SalesHeaderArchive."Document Type";
            SalesHeader."No." := SalesHeaderArchive."No.";
            OnBeforeSalesHeaderInsert(SalesHeader, SalesHeaderArchive);
            SalesHeader.IC_Typ := SalesHeaderArchive.IC_Typ;   //B40°.3
            SalesHeader.Insert(true);
            SalesHeader.TransferFields(SalesHeaderArchive);
            SalesHeader.Status := SalesHeader.Status::Open;
            //START B40°.2 ---------------------------------
            if SalesHeaderArchive."Sell-to Customer No." <> '' then
                SalesHeader.Validate("Sell-to Customer No.", SalesHeaderArchive."Sell-to Customer No.");
            //STOP  B40°.2 ---------------------------------
            if SalesHeaderArchive."Sell-to Contact No." <> '' then
                SalesHeader.Validate("Sell-to Contact No.", SalesHeaderArchive."Sell-to Contact No.")
              //START B40°.2 ---------------------------------
              //  ELSE
              //    SalesHeader.VALIDATE("Sell-to Customer No.",SalesHeaderArchive."Sell-to Customer No.");
              ;
            //STOP  B40°.2 ---------------------------------
            if SalesHeaderArchive."Bill-to Contact No." <> '' then
                SalesHeader.Validate("Bill-to Contact No.", SalesHeaderArchive."Bill-to Contact No.")
            else
                SalesHeader.Validate("Bill-to Customer No.", SalesHeaderArchive."Bill-to Customer No.");
            SalesHeader.Validate("Salesperson Code", SalesHeaderArchive."Salesperson Code");
            //START B40°.1 ---------------------------------
            if lo_re_Cust.Get(SalesHeaderArchive."Bill-to Customer No.") then
                SalesHeader.Validate("Payment Terms Code", lo_re_Cust."Payment Terms Code")
            else begin
                //STOP  B40°.1 ---------------------------------
                SalesHeader.Validate("Payment Terms Code", SalesHeaderArchive."Payment Terms Code");
                SalesHeader.Validate("Payment Discount %", SalesHeaderArchive."Payment Discount %");
            end;   //B40°.1
            SalesHeader."Shortcut Dimension 1 Code" := SalesHeaderArchive."Shortcut Dimension 1 Code";
            SalesHeader."Shortcut Dimension 2 Code" := SalesHeaderArchive."Shortcut Dimension 2 Code";
            SalesHeader."Dimension Set ID" := SalesHeaderArchive."Dimension Set ID";
            SalesHeader."Customer Disc. Group" := SalesHeaderArchive."Cust./Item Disc. Gr.";   //B40°.2

            //START B40° ---------------------------------
            if SalesHeaderArchive."Ship-to Code" <> '' then begin
                SalesHeader.Validate("Ship-to Code", SalesHeaderArchive."Ship-to Code");
            end;
            SalesHeader.Privatkunde := SalesHeaderArchive.Privatkunde;
            SalesHeader.Architekt := SalesHeaderArchive.Architekt;
            SalesHeader.GU := SalesHeaderArchive.GU;
            SalesHeader."Kom." := SalesHeaderArchive."Kom.";
            SalesHeader.IC_Typ := SalesHeaderArchive.IC_Typ;
            SalesHeader.IC_Mandant := SalesHeaderArchive.IC_Mandant;
            SalesHeader."Your Reference" := SalesHeaderArchive."Your Reference";
            SalesHeader."Kopfrabatt H" := SalesHeaderArchive."Kopfrabatt H";
            SalesHeader."Kopfrabatt I" := SalesHeaderArchive."Kopfrabatt I";
            SalesHeader."Kopfrabatt E" := SalesHeaderArchive."Kopfrabatt E";
            SalesHeader."Kopfrabatt W" := SalesHeaderArchive."Kopfrabatt W";
            SalesHeader."Kopfrabatt G" := SalesHeaderArchive."Kopfrabatt G";
            SalesHeader."Kopfrabatt T" := SalesHeaderArchive."Kopfrabatt T";
            SalesHeader.Planer := SalesHeaderArchive.Planer;
            SalesHeader.Investor := SalesHeaderArchive.Investor;
            SalesHeader."PrivatCustHeaderDisc H" := SalesHeaderArchive."PrivatCustHeaderDisc H";
            SalesHeader."PrivatCustHeaderDisc I" := SalesHeaderArchive."PrivatCustHeaderDisc I";
            SalesHeader."PrivatCustHeaderDisc E" := SalesHeaderArchive."PrivatCustHeaderDisc E";
            SalesHeader."PrivatCustHeaderDisc W" := SalesHeaderArchive."PrivatCustHeaderDisc W";
            SalesHeader."PrivatCustHeaderDisc G" := SalesHeaderArchive."PrivatCustHeaderDisc G";
            SalesHeader."PrivatCustHeaderDisc T" := SalesHeaderArchive."PrivatCustHeaderDisc T";
            SalesHeader."Job No." := SalesHeaderArchive."Job No.";
            SalesHeader."Kundenprojektnr." := SalesHeaderArchive."Kundenprojektnr.";
            SalesHeader."Shortcut Dimension 1 Code" := SalesHeaderArchive."Shortcut Dimension 1 Code";
            SalesHeader."Shortcut Dimension 2 Code" := SalesHeaderArchive."Shortcut Dimension 2 Code";
            SalesHeader."Currency Code" := SalesHeaderArchive."Currency Code";
            SalesHeader."EU 3-Party Trade" := SalesHeaderArchive."EU 3-Party Trade";
            SalesHeader."Transaction Type" := SalesHeaderArchive."Transaction Type";
            SalesHeader."Transaction Specification" := SalesHeaderArchive."Transaction Specification";
            SalesHeader."Transport Method" := SalesHeaderArchive."Transport Method";
            SalesHeader."Exit Point" := SalesHeaderArchive."Exit Point";
            SalesHeader.Area := SalesHeaderArchive.Area;
            SalesHeader.Ersteller := SalesHeaderArchive.Ersteller;
            SalesHeader.Angebotsart2 := SalesHeaderArchive.Angebotsart2;
            //STOP  B40° ---------------------------------
            //START A65° ---------------------------------
            SalesHeader.Angebotsart := SalesHeaderArchive.Angebotsart;
            SalesHeader."GU-Rabatt für Standardartikel" := SalesHeaderArchive."GU-Rabatt für Standardartikel";
            SalesHeader."GU-Rabatt für Austauschartikel" := SalesHeaderArchive."GU-Rabatt für Austauschartikel";
            SalesHeader."Zahlungscode GU" := SalesHeaderArchive."Zahlungscode GU";
            //STOP  A65° ---------------------------------
            //CLEAR(SalesHeader.Nettoprojekt);   //C73°
            Clear(SalesHeader."Release Bäderpark");   //C51°

            RecordLinkManagement.CopyLinks(SalesHeaderArchive, SalesHeader);
            SalesHeader.LinkSalesDocWithOpportunity(OldOpportunityNo);
            OnAfterTransferFromArchToSalesHeader(SalesHeader, SalesHeaderArchive);
            SalesHeader.Modify(true);
            RestoreSalesLines(SalesHeaderArchive, SalesHeader);
            SalesHeader.Status := SalesHeader.Status::Released;
            ReleaseSalesDoc.Reopen(SalesHeader);
            OnAfterRestoreSalesDocument(SalesHeader, SalesHeaderArchive);

            Message(Text003, SalesHeader."Document Type", SalesHeader."No.");
        end;

        lo_cu_SalesMgt.fnk_Cu5063_OnAfterRestoreSalesDocument(SalesHeaderArchive, SalesHeader);   //C27°
    end;

    local procedure RestoreSalesLines(var SalesHeaderArchive: Record "Sales Header Archive"; SalesHeader: Record "Sales Header")
    var
        SalesLine: Record "Sales Line";
        SalesLineArchive: Record "Sales Line Archive";
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_SalesLineMgt: Codeunit SalesLineMgt;
    begin
        RestoreSalesLineComments(SalesHeaderArchive, SalesHeader);

        SalesLineArchive.SetRange("Document Type", SalesHeaderArchive."Document Type");
        SalesLineArchive.SetRange("Document No.", SalesHeaderArchive."No.");
        SalesLineArchive.SetRange("Doc. No. Occurrence", SalesHeaderArchive."Doc. No. Occurrence");
        SalesLineArchive.SetRange("Version No.", SalesHeaderArchive."Version No.");
        if SalesLineArchive.FindSet then
            repeat
                with SalesLine do begin
                    Init;
                    TransferFields(SalesLineArchive);
                    //START B40°.8 ---------------------------------
                    // Bei Setkomponenten darf kein insert(true) gemacht werden, weil sonst kommt Fehlermeldung da
                    // das einfügen über den Set-Artikel gehandhabt wird
                    if Artikeltyp in [Artikeltyp::Setkomponente] then begin
                        Insert(false);
                    end else
                        //STOP  B40°.8 ---------------------------------
                        Insert(true);
                    OnRestoreSalesLinesOnAfterSalesLineInsert(SalesLine, SalesLineArchive);
                    if Type <> Type::" " then begin
                        //START B40°.6 ---------------------------------
                        // Keine Validierung (war vorher nur wenn Beleg noch existierte)
                        //VALIDATE("No.");
                        //IF SalesLineArchive."Variant Code" <> '' THEN
                        //  VALIDATE("Variant Code",SalesLineArchive."Variant Code");
                        //IF SalesLineArchive."Unit of Measure Code" <> '' THEN
                        //  VALIDATE("Unit of Measure Code",SalesLineArchive."Unit of Measure Code");
                        //VALIDATE("Location Code",SalesLineArchive."Location Code");
                        //IF Quantity <> 0 THEN
                        //  VALIDATE(Quantity,SalesLineArchive.Quantity);
                        //VALIDATE("Unit Price",SalesLineArchive."Unit Price");
                        //VALIDATE("Unit Cost (LCY)",SalesLineArchive."Unit Cost (LCY)");
                        //VALIDATE("Line Discount %",SalesLineArchive."Line Discount %");
                        //IF SalesLineArchive."Inv. Discount Amount" <> 0 THEN
                        //  VALIDATE("Inv. Discount Amount",SalesLineArchive."Inv. Discount Amount");
                        //IF Amount <> SalesLineArchive.Amount THEN
                        //  VALIDATE(Amount,SalesLineArchive.Amount);
                        //VALIDATE(Description,SalesLineArchive.Description);
                        //STOP  B40°.6 ---------------------------------
                    end;
                    "Shortcut Dimension 1 Code" := SalesLineArchive."Shortcut Dimension 1 Code";
                    "Shortcut Dimension 2 Code" := SalesLineArchive."Shortcut Dimension 2 Code";
                    "Dimension Set ID" := SalesLineArchive."Dimension Set ID";
                    "Deferral Code" := SalesLineArchive."Deferral Code";
                    RestoreDeferrals(DeferralUtilities.GetSalesDeferralDocType,
                      SalesLineArchive."Document Type",
                      SalesLineArchive."Document No.",
                      SalesLineArchive."Line No.",
                      SalesHeaderArchive."Doc. No. Occurrence",
                      SalesHeaderArchive."Version No.");
                    RecordLinkManagement.CopyLinks(SalesLineArchive, SalesLine);
                    SalesLine."Job Task No." := SalesLineArchive."Job Task No.";   //C02°
                    lo_cu_SalesLineMgt.fnk_FillUnitCostSales(SalesLine, SalesLine);   //C01°
                                                                                      //CLEAR(Nettoprojekt);   //C73°
                    OnAfterTransferFromArchToSalesLine(SalesLine, SalesLineArchive);
                    Modify(true);
                end;
                OnAfterRestoreSalesLine(SalesHeader, SalesLine, SalesHeaderArchive, SalesLineArchive);
            until SalesLineArchive.Next = 0;
    end;

    procedure GetNextOccurrenceNo(TableId: Integer; DocType: Option Quote,"Order",Invoice,"Credit Memo","Blanket Order","Return Order"; DocNo: Code[20]): Integer
    var
        SalesHeaderArchive: Record "Sales Header Archive";
        PurchHeaderArchive: Record "Purchase Header Archive";
    begin
        case TableId of
            DATABASE::"Sales Header":
                begin
                    SalesHeaderArchive.LockTable;
                    SalesHeaderArchive.SetRange("Document Type", DocType);
                    SalesHeaderArchive.SetRange("No.", DocNo);
                    if SalesHeaderArchive.FindLast then
                        exit(SalesHeaderArchive."Doc. No. Occurrence" + 1);

                    exit(1);
                end;
            DATABASE::"Purchase Header":
                begin
                    PurchHeaderArchive.LockTable;
                    PurchHeaderArchive.SetRange("Document Type", DocType);
                    PurchHeaderArchive.SetRange("No.", DocNo);
                    if PurchHeaderArchive.FindLast then
                        exit(PurchHeaderArchive."Doc. No. Occurrence" + 1);

                    exit(1);
                end;
        end;
    end;

    procedure GetNextVersionNo(TableId: Integer; DocType: Option Quote,"Order",Invoice,"Credit Memo","Blanket Order","Return Order"; DocNo: Code[20]; DocNoOccurrence: Integer): Integer
    var
        SalesHeaderArchive: Record "Sales Header Archive";
        PurchHeaderArchive: Record "Purchase Header Archive";
    begin
        case TableId of
            DATABASE::"Sales Header":
                begin
                    SalesHeaderArchive.LockTable;
                    SalesHeaderArchive.SetRange("Document Type", DocType);
                    SalesHeaderArchive.SetRange("No.", DocNo);
                    SalesHeaderArchive.SetRange("Doc. No. Occurrence", DocNoOccurrence);
                    if SalesHeaderArchive.FindLast then
                        exit(SalesHeaderArchive."Version No." + 1);

                    exit(1);
                end;
            DATABASE::"Purchase Header":
                begin
                    PurchHeaderArchive.LockTable;
                    PurchHeaderArchive.SetRange("Document Type", DocType);
                    PurchHeaderArchive.SetRange("No.", DocNo);
                    PurchHeaderArchive.SetRange("Doc. No. Occurrence", DocNoOccurrence);
                    if PurchHeaderArchive.FindLast then
                        exit(PurchHeaderArchive."Version No." + 1);

                    exit(1);
                end;
        end;
    end;

    procedure SalesDocArchiveGranule(): Boolean
    var
        SalesHeaderArchive: Record "Sales Header Archive";
    begin
        exit(SalesHeaderArchive.WritePermission);
    end;

    procedure PurchaseDocArchiveGranule(): Boolean
    var
        PurchaseHeaderArchive: Record "Purchase Header Archive";
    begin
        exit(PurchaseHeaderArchive.WritePermission);
    end;

    local procedure StoreSalesDocumentComments(DocType: Option; DocNo: Code[20]; DocNoOccurrence: Integer; VersionNo: Integer)
    var
        SalesCommentLine: Record "Sales Comment Line";
        SalesCommentLineArch: Record "Sales Comment Line Archive";
    begin
        SalesCommentLine.SetRange("Document Type", DocType);
        SalesCommentLine.SetRange("No.", DocNo);
        if SalesCommentLine.FindSet then
            repeat
                SalesCommentLineArch.Init;
                SalesCommentLineArch.TransferFields(SalesCommentLine);
                SalesCommentLineArch."Doc. No. Occurrence" := DocNoOccurrence;
                SalesCommentLineArch."Version No." := VersionNo;
                SalesCommentLineArch.Insert;
            until SalesCommentLine.Next = 0;
    end;

    local procedure StorePurchDocumentComments(DocType: Option; DocNo: Code[20]; DocNoOccurrence: Integer; VersionNo: Integer)
    var
        PurchCommentLine: Record "Purch. Comment Line";
        PurchCommentLineArch: Record "Purch. Comment Line Archive";
    begin
        PurchCommentLine.SetRange("Document Type", DocType);
        PurchCommentLine.SetRange("No.", DocNo);
        if PurchCommentLine.FindSet then
            repeat
                PurchCommentLineArch.Init;
                PurchCommentLineArch.TransferFields(PurchCommentLine);
                PurchCommentLineArch."Doc. No. Occurrence" := DocNoOccurrence;
                PurchCommentLineArch."Version No." := VersionNo;
                PurchCommentLineArch.Insert;
            until PurchCommentLine.Next = 0;
    end;

    procedure ArchSalesDocumentNoConfirm(var SalesHeader: Record "Sales Header")
    var
        lo_cu_SalesMgt: Codeunit SalesMgt;
    begin
        //START B40°.9 ---------------------------------
        // StoreSalesDocument(SalesHeader,FALSE);
        lo_cu_SalesMgt.FNK_RunSalesArchivingOnDemand(SalesHeader);
        //STOP  B40°.9 ---------------------------------
    end;

    procedure ArchPurchDocumentNoConfirm(var PurchHeader: Record "Purchase Header")
    begin
        StorePurchDocument(PurchHeader, false);
    end;

    local procedure StoreDeferrals(DeferralDocType: Integer; DocType: Integer; DocNo: Code[20]; LineNo: Integer; DocNoOccurrence: Integer; VersionNo: Integer)
    var
        DeferralHeaderArchive: Record "Deferral Header Archive";
        DeferralLineArchive: Record "Deferral Line Archive";
        DeferralHeader: Record "Deferral Header";
        DeferralLine: Record "Deferral Line";
    begin
        if DeferralHeader.Get(DeferralDocType, '', '', DocType, DocNo, LineNo) then begin
            DeferralHeaderArchive.Init;
            DeferralHeaderArchive.TransferFields(DeferralHeader);
            DeferralHeaderArchive."Doc. No. Occurrence" := DocNoOccurrence;
            DeferralHeaderArchive."Version No." := VersionNo;
            DeferralHeaderArchive.Insert;

            DeferralLine.SetRange("Deferral Doc. Type", DeferralDocType);
            DeferralLine.SetRange("Gen. Jnl. Template Name", '');
            DeferralLine.SetRange("Gen. Jnl. Batch Name", '');
            DeferralLine.SetRange("Document Type", DocType);
            DeferralLine.SetRange("Document No.", DocNo);
            DeferralLine.SetRange("Line No.", LineNo);
            if DeferralLine.FindSet then
                repeat
                    DeferralLineArchive.Init;
                    DeferralLineArchive.TransferFields(DeferralLine);
                    DeferralLineArchive."Doc. No. Occurrence" := DocNoOccurrence;
                    DeferralLineArchive."Version No." := VersionNo;
                    DeferralLineArchive.Insert;
                until DeferralLine.Next = 0;
        end;
    end;

    local procedure RestoreDeferrals(DeferralDocType: Integer; DocType: Integer; DocNo: Code[20]; LineNo: Integer; DocNoOccurrence: Integer; VersionNo: Integer)
    var
        DeferralHeaderArchive: Record "Deferral Header Archive";
        DeferralLineArchive: Record "Deferral Line Archive";
        DeferralHeader: Record "Deferral Header";
        DeferralLine: Record "Deferral Line";
    begin
        if DeferralHeaderArchive.Get(DeferralDocType, DocType, DocNo, DocNoOccurrence, VersionNo, LineNo) then begin
            // Updates the header if is exists already and removes all the lines
            DeferralUtilities.SetDeferralRecords(DeferralHeader,
              DeferralDocType, '', '',
              DocType, DocNo, LineNo,
              DeferralHeaderArchive."Calc. Method",
              DeferralHeaderArchive."No. of Periods",
              DeferralHeaderArchive."Amount to Defer",
              DeferralHeaderArchive."Start Date",
              DeferralHeaderArchive."Deferral Code",
              DeferralHeaderArchive."Schedule Description",
              DeferralHeaderArchive."Initial Amount to Defer",
              true,
              DeferralHeaderArchive."Currency Code");

            // Add lines as exist in the archives
            DeferralLineArchive.SetRange("Deferral Doc. Type", DeferralDocType);
            DeferralLineArchive.SetRange("Document Type", DocType);
            DeferralLineArchive.SetRange("Document No.", DocNo);
            DeferralLineArchive.SetRange("Doc. No. Occurrence", DocNoOccurrence);
            DeferralLineArchive.SetRange("Version No.", VersionNo);
            DeferralLineArchive.SetRange("Line No.", LineNo);
            if DeferralLineArchive.FindSet then
                repeat
                    DeferralLine.Init;
                    DeferralLine.TransferFields(DeferralLineArchive);
                    DeferralLine.Insert;
                until DeferralLineArchive.Next = 0;
        end else
            // Removes any lines that may have been defaulted
            DeferralUtilities.RemoveOrSetDeferralSchedule('', DeferralDocType, '', '', DocType, DocNo, LineNo, 0, 0D, '', '', true);
    end;

    local procedure RestoreSalesLineComments(SalesHeaderArchive: Record "Sales Header Archive"; SalesHeader: Record "Sales Header")
    var
        SalesCommentLineArchive: Record "Sales Comment Line Archive";
        SalesCommentLine: Record "Sales Comment Line";
        NextLine: Integer;
    begin
        SalesCommentLineArchive.SetRange("Document Type", SalesHeaderArchive."Document Type");
        SalesCommentLineArchive.SetRange("No.", SalesHeaderArchive."No.");
        SalesCommentLineArchive.SetRange("Doc. No. Occurrence", SalesHeaderArchive."Doc. No. Occurrence");
        SalesCommentLineArchive.SetRange("Version No.", SalesHeaderArchive."Version No.");
        if SalesCommentLineArchive.FindSet then
            repeat
                SalesCommentLine.Init;
                SalesCommentLine.TransferFields(SalesCommentLineArchive);
                SalesCommentLine.Insert;
            until SalesCommentLineArchive.Next = 0;

        SalesCommentLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesCommentLine.SetRange("No.", SalesHeader."No.");
        SalesCommentLine.SetRange("Document Line No.", 0);
        if SalesCommentLine.FindLast then
            NextLine := SalesCommentLine."Line No.";
        NextLine += 10000;
        SalesCommentLine.Init;
        SalesCommentLine."Document Type" := SalesHeader."Document Type";
        SalesCommentLine."No." := SalesHeader."No.";
        SalesCommentLine."Document Line No." := 0;
        SalesCommentLine."Line No." := NextLine;
        SalesCommentLine.Date := WorkDate;
        SalesCommentLine.Comment := StrSubstNo(Text004, Format(SalesHeaderArchive."Version No."));
        SalesCommentLine.Insert;
    end;

    procedure RoundSalesDeferralsForArchive(SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line")
    var
        DeferralHeader: Record "Deferral Header";
        AmtToDefer: Decimal;
        AmtToDeferACY: Decimal;
    begin
        SalesLine.SetFilter("Deferral Code", '<>%1', '');
        if SalesLine.FindSet then
            repeat
                if DeferralHeader.Get(DeferralUtilities.GetSalesDeferralDocType, '', '',
                     SalesLine."Document Type", SalesLine."Document No.", SalesLine."Line No.")
                then
                    DeferralUtilities.RoundDeferralAmount(
                      DeferralHeader, SalesHeader."Currency Code",
                      SalesHeader."Currency Factor", SalesHeader."Posting Date",
                      AmtToDeferACY, AmtToDefer);

            until SalesLine.Next = 0;
    end;

    procedure RoundPurchaseDeferralsForArchive(PurchaseHeader: Record "Purchase Header"; var PurchaseLine: Record "Purchase Line")
    var
        DeferralHeader: Record "Deferral Header";
        AmtToDefer: Decimal;
        AmtToDeferACY: Decimal;
    begin
        PurchaseLine.SetFilter("Deferral Code", '<>%1', '');
        if PurchaseLine.FindSet then
            repeat
                if DeferralHeader.Get(DeferralUtilities.GetPurchDeferralDocType, '', '',
                     PurchaseLine."Document Type", PurchaseLine."Document No.", PurchaseLine."Line No.")
                then
                    DeferralUtilities.RoundDeferralAmount(
                      DeferralHeader, PurchaseHeader."Currency Code",
                      PurchaseHeader."Currency Factor", PurchaseHeader."Posting Date",
                      AmtToDeferACY, AmtToDefer);
            until PurchaseLine.Next = 0;
    end;

    local procedure PrepareDeferralsForSalesOrder(SalesHeader: Record "Sales Header")
    var
        SalesLine: Record "Sales Line";
    begin
        if SalesHeader."Document Type" = SalesHeader."Document Type"::Order then begin
            SalesLine.Reset;
            SalesLine.SetRange("Document Type", SalesHeader."Document Type");
            SalesLine.SetRange("Document No.", SalesHeader."No.");
            SalesLine.SetFilter("Qty. Invoiced (Base)", '<>%1', 0);
            if SalesLine.IsEmpty then
                exit;
            RoundSalesDeferralsForArchive(SalesHeader, SalesLine);
        end;
    end;

    local procedure PrepareDeferralsPurchaseOrder(PurchaseHeader: Record "Purchase Header")
    var
        PurchaseLine: Record "Purchase Line";
    begin
        if PurchaseHeader."Document Type" = PurchaseHeader."Document Type"::Order then begin
            PurchaseLine.Reset;
            PurchaseLine.SetRange("Document Type", PurchaseHeader."Document Type");
            PurchaseLine.SetRange("Document No.", PurchaseHeader."No.");
            PurchaseLine.SetFilter("Qty. Invoiced (Base)", '<>%1', 0);
            if PurchaseLine.IsEmpty then
                exit;
            RoundPurchaseDeferralsForArchive(PurchaseHeader, PurchaseLine);
        end;
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterAutoArchivePurchDocument(var PurchaseHeader: Record "Purchase Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterAutoArchiveSalesDocument(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStoreSalesDocument(var SalesHeader: Record "Sales Header"; var SalesHeaderArchive: Record "Sales Header Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStoreSalesLineArchive(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; var SalesHeaderArchive: Record "Sales Header Archive"; var SalesLineArchive: Record "Sales Line Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStorePurchDocument(var PurchaseHeader: Record "Purchase Header"; var PurchaseHeaderArchive: Record "Purchase Header Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterStorePurchLineArchive(var PurchHeader: Record "Purchase Header"; var PurchLine: Record "Purchase Line"; var PurchHeaderArchive: Record "Purchase Header Archive"; var PurchLineArchive: Record "Purchase Line Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterRestoreSalesDocument(var SalesHeader: Record "Sales Header"; var SalesHeaderArchive: Record "Sales Header Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterRestoreSalesLine(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; var SalesHeaderArchive: Record "Sales Header Archive"; var SalesLineArchive: Record "Sales Line Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterSalesHeaderArchiveInsert(var SalesHeaderArchive: Record "Sales Header Archive"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPurchHeaderArchiveInsert(var PurchaseHeaderArchive: Record "Purchase Header Archive"; PurchaseHeader: Record "Purchase Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterTransferFromArchToSalesHeader(var SalesHeader: Record "Sales Header"; var SalesHeaderArchive: Record "Sales Header Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterTransferFromArchToSalesLine(var SalesLine: Record "Sales Line"; var SalesLineArchive: Record "Sales Line Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeAutoArchiveSalesDocument(var SalesHeader: Record "Sales Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeAutoArchivePurchDocument(var PurchaseHeader: Record "Purchase Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesHeaderInsert(var SalesHeader: Record "Sales Header"; SalesHeaderArchive: Record "Sales Header Archive")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRestoreSalesDocument(var SalesHeaderArchive: Record "Sales Header Archive"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfDocumentIsPartiallyPosted(var SalesHeaderArchive: Record "Sales Header Archive"; var DoCheck: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesHeaderArchiveInsert(var SalesHeaderArchive: Record "Sales Header Archive"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeSalesLineArchiveInsert(var SalesLineArchive: Record "Sales Line Archive"; SalesLine: Record "Sales Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePurchHeaderArchiveInsert(var PurchaseHeaderArchive: Record "Purchase Header Archive"; PurchaseHeader: Record "Purchase Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePurchLineArchiveInsert(var PurchaseLineArchive: Record "Purchase Line Archive"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRestoreDocumentOnAfterDeleteSalesHeader(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRestoreDocumentOnBeforeDeleteSalesHeader(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRestoreSalesLinesOnAfterSalesLineInsert(var SalesLine: Record "Sales Line"; var SalesLineArchive: Record "Sales Line Archive")
    begin
    end;
}

