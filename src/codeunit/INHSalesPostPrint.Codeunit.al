codeunit 50135 INHSalesPostPrint
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // Axx°          RBI  25.07.08  Anpassungen in CU übernommen
    // Axx°.1        SSC  22.05.18  Richtige Belegnr. zum drucken verwenden
    // B28°          SSC  10.09.14  Bonusgutschrift
    // 
    // UPGBC140 22.05.13 Companial_MGU Updated old standard with new

    TableNo = "Sales Header";

    trigger OnRun()
    var
        SalesHeader: Record "Sales Header";
    begin
        SalesHeader.Copy(Rec);
        Code(SalesHeader);
        Rec := SalesHeader;
    end;

    var
        ShipInvoiceQst: Label '&Ship,&Invoice,Ship &and Invoice';
        PostAndPrintQst: Label 'Do you want to post and print the %1?', Comment = '%1 = Document Type';
        PostAndEmailQst: Label 'Do you want to post and email the %1?', Comment = '%1 = Document Type';
        ReceiveInvoiceQst: Label '&Receive,&Invoice,Receive &and Invoice';
        SendReportAsEmail: Boolean;

    [Scope('Internal')]
    procedure PostAndEmail(var ParmSalesHeader: Record "Sales Header")
    var
        SalesHeader: Record "Sales Header";
    begin
        SendReportAsEmail := true;
        SalesHeader.Copy(ParmSalesHeader);
        Code(SalesHeader);
        ParmSalesHeader := SalesHeader;
    end;

    local procedure "Code"(var SalesHeader: Record "Sales Header")
    var
        SalesSetup: Record "Sales & Receivables Setup";
        SalesPostViaJobQueue: Codeunit "Sales Post via Job Queue";
        HideDialog: Boolean;
        IsHandled: Boolean;
        DefaultOption: Integer;
        "+++LO_VAR_INHAUS+++": Boolean;
        BatchProcessingParameter: Record "Batch Processing Parameter";
        BatchProcessingSessionMap: Record "Batch Processing Session Map";
        lo_cu_SalesPost: Codeunit "Sales-Post";
        BatchPostParameterTypes: Codeunit "Batch Post Parameter Types";
        BatchID: Guid;
    begin
        HideDialog := false;
        IsHandled := false;
        DefaultOption := 3;
        OnBeforeConfirmPost(SalesHeader, HideDialog, IsHandled, SendReportAsEmail, DefaultOption);
        if IsHandled then
            exit;

        if not HideDialog then
            if not ConfirmPost(SalesHeader, DefaultOption) then
                exit;

        OnAfterConfirmPost(SalesHeader);

        SalesSetup.Get;
        if SalesSetup."Post & Print with Job Queue" and not SendReportAsEmail then
            SalesPostViaJobQueue.EnqueueSalesDoc(SalesHeader)
        else begin
            //START Axx° ---------------------------------
            //CODEUNIT.RUN(CODEUNIT::"Sales-Post",SalesHeader);
            if SalesHeader.BonusCreditMemo and (SalesHeader."Document Type" in [SalesHeader."Document Type"::"Credit Memo"]) then begin
                //B28° Ausnahme: Buchungsdatum <> Workdate erlaubt
            end else begin
                //>> UPGBC140_MGU Start
                //lo_cu_SalesPost.SetPostingDate(TRUE,TRUE,WORKDATE);
                BatchID := CreateGuid;
                BatchProcessingSessionMap.Init;

                BatchProcessingSessionMap."Record ID" := SalesHeader.RecordId;
                BatchProcessingSessionMap."Batch ID" := BatchID;
                BatchProcessingSessionMap."User ID" := UserSecurityId;
                BatchProcessingSessionMap."Session ID" := SessionId;
                BatchProcessingSessionMap.Insert;

                BatchProcessingParameter.Init;
                BatchProcessingParameter."Batch ID" := BatchID;
                BatchProcessingParameter."Parameter Id" := BatchPostParameterTypes.ReplaceDocumentDate;
                BatchProcessingParameter."Parameter Value" := Format(true);
                BatchProcessingParameter.Insert;

                BatchProcessingParameter.Init;
                BatchProcessingParameter."Batch ID" := BatchID;
                BatchProcessingParameter."Parameter Id" := BatchPostParameterTypes.ReplacePostingDate;
                BatchProcessingParameter."Parameter Value" := Format(true);
                BatchProcessingParameter.Insert;

                BatchProcessingParameter.Init;
                BatchProcessingParameter."Batch ID" := BatchID;
                BatchProcessingParameter."Parameter Id" := BatchPostParameterTypes.PostingDate;
                BatchProcessingParameter."Parameter Value" := Format(WorkDate);
                BatchProcessingParameter.Insert;
                //<< UPGBC140_MGU End
            end;
            lo_cu_SalesPost.Run(SalesHeader);
            //>> UPGBC140_MGU Start
            if (not IsNullGuid(BatchID)) then begin
                BatchProcessingParameter.SetRange("Batch ID", BatchID);
                BatchProcessingParameter.DeleteAll;
                BatchProcessingSessionMap.SetRange("Batch ID", BatchID);
                BatchProcessingSessionMap.DeleteAll;
                Clear(BatchID);
            end;
            //<< UPGBC140_MGU End
            //STOP  Axx° ---------------------------------
            GetReport(SalesHeader);
        end;

        OnAfterPost(SalesHeader);
        Commit;
    end;

    procedure GetReport(var SalesHeader: Record "Sales Header")
    var
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforeGetReport(SalesHeader, IsHandled, SendReportAsEmail);
        if IsHandled then
            exit;

        with SalesHeader do
            case "Document Type" of
                "Document Type"::Order:
                    begin
                        if Ship then
                            PrintShip(SalesHeader);
                        if Invoice then
                            PrintInvoice(SalesHeader);
                    end;
                "Document Type"::Invoice:
                    PrintInvoice(SalesHeader);
                "Document Type"::"Return Order":
                    begin
                        if Receive then
                            PrintReceive(SalesHeader);
                        if Invoice then
                            PrintCrMemo(SalesHeader);
                    end;
                "Document Type"::"Credit Memo":
                    PrintCrMemo(SalesHeader);
            end;
    end;

    local procedure ConfirmPost(var SalesHeader: Record "Sales Header"; DefaultOption: Integer): Boolean
    var
        ConfirmManagement: Codeunit "Confirm Management";
        Selection: Integer;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_ICMgt: Codeunit ICMgt;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_cu_SalesPost: Codeunit "Sales-Post";
    begin
        if DefaultOption > 3 then
            DefaultOption := 3;
        if DefaultOption <= 0 then
            DefaultOption := 1;

        with SalesHeader do begin
            case "Document Type" of
                "Document Type"::Order:
                    begin
                        //START Axx° ---------------------------------
                        //Selection := STRMENU(ShipInvoiceQst,DefaultOption);
                        //IF Selection = 0 THEN
                        //  EXIT(FALSE);
                        //Ship := Selection IN [1,3];
                        //Invoice := Selection IN [2,3];
                        if lo_cu_SalesMgt.FNK_PrüfenVorBuchen(SalesHeader) then begin
                            if Confirm('Wollen Sie Liefern & Fakturieren ?', true) then begin
                                Ship := true;
                                Invoice := true;
                            end else
                                Error('Funktion abgebrochen !');
                        end else begin
                            Selection := StrMenu(ShipInvoiceQst, 1);   // Liefern vorbelegen
                            if Selection = 0 then
                                exit;
                            Ship := Selection in [1, 3];
                            Invoice := Selection in [2, 3];
                        end;
                        //STOP  Axx° ---------------------------------
                    end;
                "Document Type"::"Return Order":
                    begin
                        //START Axx° ---------------------------------
                        //Selection := STRMENU(ReceiveInvoiceQst,DefaultOption);
                        Selection := StrMenu(ReceiveInvoiceQst, 1);   // Liefern vorbelegen
                                                                      //STOP  Axx° ---------------------------------
                        if Selection = 0 then
                            exit(false);
                        Receive := Selection in [1, 3];
                        Invoice := Selection in [2, 3];
                    end
                else
                    if not ConfirmManagement.ConfirmProcess(
                         StrSubstNo(ConfirmationMessage, "Document Type"), true)
                    then
                        exit(false);
            end;
            "Print Posted Documents" := true;
        end;
        exit(true);
    end;

    local procedure ConfirmationMessage(): Text
    begin
        if SendReportAsEmail then
            exit(PostAndEmailQst);
        exit(PostAndPrintQst);
    end;

    local procedure PrintReceive(SalesHeader: Record "Sales Header")
    var
        ReturnRcptHeader: Record "Return Receipt Header";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforePrintReceive(SalesHeader, SendReportAsEmail, IsHandled);
        if IsHandled then
            exit;

        ReturnRcptHeader."No." := SalesHeader."Last Return Receipt No.";
        if ReturnRcptHeader.Find then;
        ReturnRcptHeader.SetRecFilter;

        if SendReportAsEmail then
            ReturnRcptHeader.EmailRecords(true)
        else
            ReturnRcptHeader.PrintRecords(false);
    end;

    local procedure PrintInvoice(SalesHeader: Record "Sales Header")
    var
        SalesInvHeader: Record "Sales Invoice Header";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforePrintInvoice(SalesHeader, SendReportAsEmail, IsHandled);
        if IsHandled then
            exit;

        if SalesHeader."Last Posting No." = '' then begin
            //START Axx°.1 ---------------------------------
            //  SalesInvHeader."No." := SalesHeader."No."
            if SalesHeader."Posting No." = '' then begin
                SalesInvHeader."No." := SalesHeader."No.";
            end else begin
                SalesInvHeader."No." := SalesHeader."Posting No.";
            end;
            //STOP  Axx°.1 ---------------------------------
        end else
            SalesInvHeader."No." := SalesHeader."Last Posting No.";
        SalesInvHeader.Find;
        SalesInvHeader.SetRecFilter;

        if SendReportAsEmail then
            SalesInvHeader.EmailRecords(true)
        else
            SalesInvHeader.PrintRecords(false);
    end;

    local procedure PrintShip(SalesHeader: Record "Sales Header")
    var
        SalesShptHeader: Record "Sales Shipment Header";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforePrintShip(SalesHeader, SendReportAsEmail, IsHandled);
        if IsHandled then
            exit;

        SalesShptHeader."No." := SalesHeader."Last Shipping No.";
        if SalesShptHeader.Find then;
        SalesShptHeader.SetRecFilter;

        //START Axx° ---------------------------------
        if (SalesHeader.Rechnungsart = SalesHeader.Rechnungsart::Barzahler) then
            exit;
        //STOP  Axx° ---------------------------------

        if SendReportAsEmail then
            SalesShptHeader.EmailRecords(true)
        else
            SalesShptHeader.PrintRecords(false);
    end;

    local procedure PrintCrMemo(SalesHeader: Record "Sales Header")
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        IsHandled: Boolean;
    begin
        IsHandled := false;
        OnBeforePrintCrMemo(SalesHeader, SendReportAsEmail, IsHandled);
        if IsHandled then
            exit;

        if SalesHeader."Last Posting No." = '' then begin
            //START Axx°.1 ---------------------------------
            //  SalesCrMemoHeader."No." := SalesHeader."No."
            if SalesHeader."Posting No." = '' then begin
                SalesCrMemoHeader."No." := SalesHeader."No.";
            end else begin
                SalesCrMemoHeader."No." := SalesHeader."Posting No.";
            end;
            //STOP  Axx°.1 ---------------------------------
        end else
            SalesCrMemoHeader."No." := SalesHeader."Last Posting No.";
        SalesCrMemoHeader.Find;
        SalesCrMemoHeader.SetRecFilter;

        if SendReportAsEmail then
            SalesCrMemoHeader.EmailRecords(true)
        else
            SalesCrMemoHeader.PrintRecords(false);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPost(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterConfirmPost(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConfirmPost(var SalesHeader: Record "Sales Header"; var HideDialog: Boolean; var IsHandled: Boolean; var SendReportAsEmail: Boolean; var DefaultOption: Integer)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetReport(var SalesHeader: Record "Sales Header"; var IsHandled: Boolean; SendReportAsEmail: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePrintInvoice(var SalesHeader: Record "Sales Header"; SendReportAsEmail: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePrintCrMemo(var SalesHeader: Record "Sales Header"; SendReportAsEmail: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePrintReceive(var SalesHeader: Record "Sales Header"; SendReportAsEmail: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePrintShip(var SalesHeader: Record "Sales Header"; SendReportAsEmail: Boolean; var IsHandled: Boolean)
    begin
    end;
}

