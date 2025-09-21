codeunit 50160 INHWhseSalesRelease
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // A08°          RBI  29.07.08  Anpassungen in CU übernommen.
    // C54°          SSC  13.08.19  Info ob Artikel gerade im Wareneingang sind
    // C91°          SSC  03.07.25  Anzahlung
    // C98°          SSC  07.11.24  Nicht nur auf Gesperrt::Alle prüfen


    trigger OnRun()
    begin
    end;

    var
        WhseRqst: Record "Warehouse Request";
        SalesLine: Record "Sales Line";
        Location: Record Location;
        OldLocationCode: Code[10];
        First: Boolean;

    procedure Release(SalesHeader: Record "Sales Header")
    var
        WhseType: Option Inbound,Outbound;
        OldWhseType: Option Inbound,Outbound;
        IsHandled: Boolean;
    begin
        OnBeforeRelease(SalesHeader);

        with SalesHeader do begin
            IsHandled := false;
            OnBeforeReleaseSetWhseRequestSourceDocument(SalesHeader, WhseRqst, IsHandled);
            if not IsHandled then
                case "Document Type" of
                    "Document Type"::Order:
                        WhseRqst."Source Document" := WhseRqst."Source Document"::"Sales Order";
                    "Document Type"::"Return Order":
                        WhseRqst."Source Document" := WhseRqst."Source Document"::"Sales Return Order";
                    else
                        exit;
                end;

            SalesLine.SetCurrentKey("Document Type", "Document No.", "Location Code");
            SalesLine.SetRange("Document Type", "Document Type");
            SalesLine.SetRange("Document No.", "No.");
            SalesLine.SetRange(Type, SalesLine.Type::Item);
            SalesLine.SetFilter("No.", '<>%1', '');   //A08°
            SalesLine.SetRange("Drop Shipment", false);
            //A08°:SalesLine.SETRANGE("Job No.",'');
            OnAfterReleaseSetFilters(SalesLine, SalesHeader);
            if SalesLine.FindSet then begin
                First := true;
                repeat
                    if (("Document Type" = "Document Type"::Order) and (SalesLine.Quantity >= 0)) or
                       (("Document Type" = "Document Type"::"Return Order") and (SalesLine.Quantity < 0))
                    then
                        WhseType := WhseType::Outbound
                    else
                        WhseType := WhseType::Inbound;

                    if First or (SalesLine."Location Code" <> OldLocationCode) or (WhseType <> OldWhseType) then
                        CreateWhseRqst(SalesHeader, SalesLine, WhseType);

                    OnAfterReleaseOnAfterCreateWhseRequest(SalesHeader, SalesLine, WhseType, First, OldWhseType, OldLocationCode);

                    First := false;
                    OldLocationCode := SalesLine."Location Code";
                    OldWhseType := WhseType;
                until SalesLine.Next = 0;
            end;

            WhseRqst.Reset;
            WhseRqst.SetCurrentKey("Source Type", "Source Subtype", "Source No.");
            WhseRqst.SetRange(Type, WhseRqst.Type);
            WhseRqst.SetSourceFilter(DATABASE::"Sales Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", Status::Open);
            if not WhseRqst.IsEmpty then
                WhseRqst.DeleteAll(true);
        end;

        OnAfterRelease(SalesHeader);
    end;

    procedure Reopen(SalesHeader: Record "Sales Header")
    var
        WhseRqst: Record "Warehouse Request";
        IsHandled: Boolean;
    begin
        OnBeforeReopen(SalesHeader);

        with SalesHeader do begin
            IsHandled := false;
            OnBeforeReopenSetWhseRequestSourceDocument(SalesHeader, WhseRqst, IsHandled);

            WhseRqst.Reset;
            WhseRqst.SetCurrentKey("Source Type", "Source Subtype", "Source No.");
            if IsHandled then
                WhseRqst.SetRange(Type, WhseRqst.Type);
            WhseRqst.SetSourceFilter(DATABASE::"Sales Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", Status::Released);
            WhseRqst.LockTable;
            if not WhseRqst.IsEmpty then begin
                WhseRqst.ModifyAll("Document Status", WhseRqst."Document Status"::Open);
                WhseRqst.ModifyAll(Auftragsstatus, Lieferstatus);   //A08°
            end;
        end;

        OnAfterReopen(SalesHeader);
    end;

    [Scope('Internal')]
    procedure UpdateExternalDocNoForReleasedOrder(SalesHeader: Record "Sales Header")
    begin
        with SalesHeader do begin
            WhseRqst.Reset;
            WhseRqst.SetCurrentKey("Source Type", "Source Subtype", "Source No.");
            WhseRqst.SetSourceFilter(DATABASE::"Sales Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", Status::Released);
            if not WhseRqst.IsEmpty then
                WhseRqst.ModifyAll("External Document No.", "External Document No.");
        end;
    end;

    local procedure CreateWhseRqst(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; WhseType: Option Inbound,Outbound)
    var
        SalesLine2: Record "Sales Line";
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_re_Cust: Record Customer;
        lo_re_WhseRqst: Record "Warehouse Request";
        lo_cu_LogisticsMgt: Codeunit LogisticsMgt;
        lo_cu_PrePaymentPlanMgmt: Codeunit "PrePayment Plan Mgmt.";
        lo_da_KommDatum: Date;
    begin
        if ((WhseType = WhseType::Outbound) and
            (Location.RequireShipment(SalesLine."Location Code") or
             Location.RequirePicking(SalesLine."Location Code"))) or
           ((WhseType = WhseType::Inbound) and
            (Location.RequireReceive(SalesLine."Location Code") or
             Location.RequirePutaway(SalesLine."Location Code")))
        then begin
            SalesLine2.Copy(SalesLine);
            SalesLine2.SetRange("Location Code", SalesLine."Location Code");
            SalesLine2.SetFilter("No.", '<>%1', '');   //A08°
            SalesLine2.SetRange("Unit of Measure Code", '');
            if SalesLine2.FindFirst then
                SalesLine2.TestField("Unit of Measure Code");

            WhseRqst.Type := WhseType;
            WhseRqst."Source Type" := DATABASE::"Sales Line";
            WhseRqst."Source Subtype" := SalesHeader."Document Type";
            WhseRqst."Source No." := SalesHeader."No.";
            WhseRqst."Shipment Method Code" := SalesHeader."Shipment Method Code";
            WhseRqst."Shipping Agent Code" := SalesHeader."Shipping Agent Code";
            WhseRqst."Shipping Advice" := SalesHeader."Shipping Advice";
            WhseRqst."Document Status" := SalesHeader.Status::Released;
            WhseRqst."Location Code" := SalesLine."Location Code";
            WhseRqst."Destination Type" := WhseRqst."Destination Type"::Customer;
            WhseRqst."Destination No." := SalesHeader."Sell-to Customer No.";
            WhseRqst."External Document No." := SalesHeader."External Document No.";
            if WhseType = WhseType::Inbound then
                WhseRqst."Expected Receipt Date" := SalesHeader."Shipment Date"
            else
                WhseRqst."Shipment Date" := SalesHeader."Shipment Date";
            SalesHeader.SetRange("Location Filter", SalesLine."Location Code");
            SalesHeader.CalcFields("Completely Shipped");
            WhseRqst."Completely Handled" := SalesHeader."Completely Shipped";
            OnBeforeCreateWhseRequest(WhseRqst, SalesHeader, SalesLine, WhseType);
            //START A08° ---------------------------------
            WhseRqst.Auftragsstatus := SalesHeader.Lieferstatus;
            WhseRqst.Lieferdatum := lo_cu_LogisticsMgt.FNK_VKKopf_LiefdatuminWATopf(SalesHeader, 1);
            if (WhseRqst.Lieferdatum = 0D) then
                WhseRqst.Lieferdatum := SalesHeader."Promised Delivery Date";
            WhseRqst.Ladenverkauf := SalesHeader."Ladenverkauf/Direktlieferung";
            //STOP  A08° ---------------------------------
            WhseRqst."Items in Whse Receipt" := SalesHeader."Items in Whse Receipt";   //C54°
            if not WhseRqst.Insert then
                WhseRqst.Modify;
            OnAfterCreateWhseRequest(WhseRqst, SalesHeader, SalesLine, WhseType);

            //START A08° ---------------------------------
            if GuiAllowed then begin
                lo_da_KommDatum := lo_cu_LogisticsMgt.FNK_KommDatumErrechnen(0);
                if (SalesHeader.IC_Typ = SalesHeader.IC_Typ::Auftrag) and (SalesHeader."Promised Delivery Date" <= lo_da_KommDatum) and
                   (SalesHeader.Auftragsart <> 'AB') and (SalesHeader."Document Type" = SalesHeader."Document Type"::Order)
                then begin
                    lo_re_WhseRqst.Reset;
                    lo_re_WhseRqst.SetRange(Lieferdatum, 0D, lo_da_KommDatum);
                    lo_re_WhseRqst.SetRange(Type, lo_re_WhseRqst.Type::Outbound);
                    lo_re_WhseRqst.SetRange("Document Status", lo_re_WhseRqst."Document Status"::Released);
                    lo_re_WhseRqst.SetRange("Completely Handled", false);
                    lo_re_WhseRqst.SetRange("Location Code", SalesHeader."Location Code");
                    lo_re_WhseRqst.SetRange(Auftragsstatus, lo_re_WhseRqst.Auftragsstatus::"Lieferfähig");
                    lo_re_WhseRqst.SetRange("Source Document", lo_re_WhseRqst."Source Document"::"Sales Order");
                    lo_re_WhseRqst.SetRange("Source No.", SalesHeader."No.");
                    if lo_re_WhseRqst.FindFirst then begin
                        //START C98° ---------------------------------
                        //IF lo_re_Cust.GET(SalesHeader."Sell-to Customer No.") AND (lo_re_Cust.Blocked=lo_re_Cust.Blocked::All) THEN BEGIN
                        if lo_re_Cust.Get(SalesHeader."Sell-to Customer No.") and (lo_re_Cust.Blocked <> lo_re_Cust.Blocked::" ") then begin
                            //STOP  C98° ---------------------------------
                            Message('ACHTUNG FEHLER: Debitor %1 ist gesperrt!', SalesHeader."Sell-to Customer No.");
                        end else begin
                            //START C91° ---------------------------------
                            if lo_cu_PrePaymentPlanMgmt.fnk_CheckIfOrderIsBlocked(SalesHeader.IC_Auftrag, false, false) then begin
                                Message('Anzahlung ausstehend, IC_Auftrag ' + Format(SalesHeader.IC_Auftrag) + ' wird erst nach Bezahlung in die Logistik versandt.');
                            end else
                                //STOP  C91° ---------------------------------
                                Message('IC_Auftrag ' + Format(SalesHeader.IC_Auftrag) + ' wurde in die Logistik versandt.');
                        end;
                    end else begin
                        Message('ACHTUNG FEHLER: IC_Auftrag ' + Format(SalesHeader.IC_Auftrag) + ' wurde NICHT in die Logistik versandt.');
                    end;
                end;
            end;
            //STOP  A08° ---------------------------------
        end;
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateWhseRequest(var WhseRqst: Record "Warehouse Request"; var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; WhseType: Option Inbound,Outbound)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateWhseRequest(var WhseRqst: Record "Warehouse Request"; var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; WhseType: Option Inbound,Outbound)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterRelease(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterReleaseSetFilters(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterReleaseOnAfterCreateWhseRequest(var SalesHeader: Record "Sales Header"; var SalesLine: Record "Sales Line"; WhseType: Option; First: Boolean; OldWhseType: Option; OldLocationCode: Code[10])
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterReopen(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeRelease(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeReleaseSetWhseRequestSourceDocument(var SalesHeader: Record "Sales Header"; var WarehouseRequest: Record "Warehouse Request"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeReopen(var SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeReopenSetWhseRequestSourceDocument(var SalesHeader: Record "Sales Header"; var WarehouseRequest: Record "Warehouse Request"; var IsHandled: Boolean)
    begin
    end;
}

