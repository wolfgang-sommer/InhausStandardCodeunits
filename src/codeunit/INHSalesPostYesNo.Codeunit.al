codeunit 50136 INHSalesPostYesNo
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
    // B28°          SSC  12.09.14  Bonusgutschrift anders datieren erlauben
    // 
    // UPGBC140 22.05.13 Companial_MGU Updated old standard with new

    EventSubscriberInstance = Manual;
    TableNo = "Sales Header";

    trigger OnRun()
    var
        SalesHeader: Record "Sales Header";
    begin
        if not Find then
            Error(NothingToPostErr);

        SalesHeader.Copy(Rec);
        Code(SalesHeader, false);
        Rec := SalesHeader;
    end;

    var
        ShipInvoiceQst: Label '&Ship,&Invoice,Ship &and Invoice';
        PostConfirmQst: Label 'Do you want to post the %1?', Comment = '%1 = Document Type';
        ReceiveInvoiceQst: Label '&Receive,&Invoice,Receive &and Invoice';
        NothingToPostErr: Label 'There is nothing to post.';

    [Scope('Internal')]
    procedure PostAndSend(var SalesHeader: Record "Sales Header")
    var
        SalesHeaderToPost: Record "Sales Header";
    begin
        SalesHeaderToPost.Copy(SalesHeader);
        Code(SalesHeaderToPost, true);
        SalesHeader := SalesHeaderToPost;
    end;

    local procedure "Code"(var SalesHeader: Record "Sales Header"; PostAndSend: Boolean)
    var
        SalesSetup: Record "Sales & Receivables Setup";
        SalesPostViaJobQueue: Codeunit "Sales Post via Job Queue";
        HideDialog: Boolean;
        IsHandled: Boolean;
        DefaultOption: Integer;
        "+++LO_VAR_INHAUS+++": Boolean;
        BatchProcessingParameter: Record "Batch Processing Parameter";
        BatchProcessingSessionMap: Record "Batch Processing Session Map";
        lo_cu_ICMgt: Codeunit ICMgt;
        lo_cu_SalesMgt: Codeunit SalesMgt;
        lo_cu_SalesPost: Codeunit "Sales-Post";
        BatchPostParameterTypes: Codeunit "Batch Post Parameter Types";
        BatchID: Guid;
    begin
        HideDialog := false;
        IsHandled := false;
        DefaultOption := 3;
        OnBeforeConfirmSalesPost(SalesHeader, HideDialog, IsHandled, DefaultOption, PostAndSend);
        if IsHandled then
            exit;

        if not HideDialog then
            if not ConfirmPost(SalesHeader, DefaultOption) then
                exit;

        OnAfterConfirmPost(SalesHeader);

        lo_cu_ICMgt.FNK_Check_Function(SalesHeader, 1);   //Axx°

        SalesSetup.Get;
        if SalesSetup."Post with Job Queue" and not PostAndSend then
            SalesPostViaJobQueue.EnqueueSalesDoc(SalesHeader)
        //START Axx° ---------------------------------
        //ELSE
        //  CODEUNIT.RUN(CODEUNIT::"Sales-Post",SalesHeader);
        else begin
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
        end;
        //STOP  Axx° ---------------------------------

        OnAfterPost(SalesHeader);
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
                        //Ship := Selection IN [1,3];
                        //Invoice := Selection IN [2,3];
                        //IF Selection = 0 THEN
                        //  EXIT(FALSE);
                        if lo_cu_SalesMgt.FNK_PrüfenVorBuchen(SalesHeader) then begin
                            if Confirm('Wollen Sie Liefern & Fakturieren ?', true) then begin
                                Ship := true;
                                Invoice := true;
                            end else
                                Error('Funktion abgebrochen !');
                        end else begin
                            Selection := StrMenu(ShipInvoiceQst, 1);   //Liefern vorbelegen
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
                        Selection := StrMenu(ReceiveInvoiceQst, 1);   //Liefern vorbelegen
                                                                      //STOP  Axx° ---------------------------------
                        if Selection = 0 then
                            exit(false);
                        Receive := Selection in [1, 3];
                        Invoice := Selection in [2, 3];
                    end
                else
                    if not ConfirmManagement.GetResponse
                         StrSubstNo(PostConfirmQst, Format("Document Type")), true)
                    then
                        exit(false);
            end;
            "Print Posted Documents" := false;
        end;
        exit(true);
    end;

    procedure Preview(var SalesHeader: Record "Sales Header")
    var
        SalesPostYesNo: Codeunit "Sales-Post (Yes/No)";
        GenJnlPostPreview: Codeunit "Gen. Jnl.-Post Preview";
    begin
        BindSubscription(SalesPostYesNo);
        GenJnlPostPreview.Preview(SalesPostYesNo, SalesHeader);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPost(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterConfirmPost(var SalesHeader: Record "Sales Header")
    begin
    end;

    [EventSubscriber(ObjectType::Codeunit, 19, 'OnRunPreview', '', false, false)]
    local procedure OnRunPreview(var Result: Boolean; Subscriber: Variant; RecVar: Variant)
    var
        SalesHeader: Record "Sales Header";
        SalesPost: Codeunit "Sales-Post";
    begin
        with SalesHeader do begin
            Copy(RecVar);
            Receive := "Document Type" = "Document Type"::"Return Order";
            Ship := "Document Type" in ["Document Type"::Order, "Document Type"::Invoice, "Document Type"::"Credit Memo"];
            Invoice := true;
        end;

        OnRunPreviewOnAfterSetPostingFlags(SalesHeader);

        SalesPost.SetPreviewMode(true);
        Result := SalesPost.Run(SalesHeader);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnRunPreviewOnAfterSetPostingFlags(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConfirmSalesPost(var SalesHeader: Record "Sales Header"; var HideDialog: Boolean; var IsHandled: Boolean; var DefaultOption: Integer; var PostAndSend: Boolean)
    begin
    end;
}

