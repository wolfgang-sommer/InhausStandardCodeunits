codeunit 50116 INHGetSourceDocOutbound
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // A08°          RBI  02.06.08  Funktion "GetSingleOutboundDoc"für den Warenausgang geändert.
    // A08°.1        SSC  26.06.18  Möglichkeit mehrere WA's über den Code zu erstellen
    // A08°.2        SSC  01.10.18  Es darf immer nur 1 Auftrag in einem WA landen; Bug abfangen
    // A28°.1        SSC  17.12.14  Ab einem Tag vor Inventur keine Umlagerungen mehr zulassen
    //               SSC  10.12.15  Datum dynamisch bestimmen
    //               SSC  09.12.21  NT am Tag davor noch zulassen
    // B43°.1        SSC  20.06.12  Kreditlimitprüfung beim Warenausgang erstellen
    // B43°.2        SSC  01.02.18  Fehler Nulldivision wenn Währungsfaktor=0 ist durch Umstellung vom Feld "Fester Wechselkursbetrag"
    //                              in der Währungswechselkurs Tabelle
    // B43°.4        SSC  23.11.20  Beim vorrüsten muss der aktuelle Auftrag immer berücksichtigt werden, auch wenn das Lieferdatum noch mehr als 2 Tage in der Zukunft liegt
    // C34°.6        SSC  24.01.22  Import in Shipping beim anlegen vom Warenausgang
    // C54°          RBI  16.05.19  fnk_GetSingleOutboundDoc - CLEAR(Report) eingebaut wegen Stapelausführung
    //               SSC  07.12.19  Neues Feld Verantwortlicher füllen
    //               SSC  17.12.20  Kurz vor der Inventur "Ware holen" trotzdem erlauben; NAS User darf auch keine WA's anlegen
    // C83°          SSC  06.12.22  Standard für SST
    // C91°          SSC  27.01.25  Anzahlung


    trigger OnRun()
    begin
    end;

    var
        Text001: Label 'If %1 is %2 in %3 no. %4, then all associated lines where type is %5 must use the same location.';
        Text002: Label 'The warehouse shipment was not created because the Shipping Advice field is set to Complete, and item no. %1 is not available in location code %2.\\You can create the warehouse shipment by either changing the Shipping Advice field to Partial in %3 no. %4 or by manually filling in the warehouse shipment document.';
        Text003: Label 'The warehouse shipment was not created because an open warehouse shipment exists for the Sales Header and Shipping Advice is %1.\\You must add the item(s) as new line(s) to the existing warehouse shipment or change Shipping Advice to Partial.';
        Text004: Label 'No %1 was found. The warehouse shipment could not be created.';
        GetSourceDocuments: Report "Get Source Documents";
        "+++TE_INHAUS+++": ;
        TextMultipleSourceNos: Label 'Fehler: Mehrere Herkunftsnr.(%1, %2) in einem Beleg.';
        TextWhseLineExists: Label 'Es kann kein weiterer Herkunftsbelege geholt werden, da bereits Zeilen vorhanden sind!';
        "+++VAR_INHAUS+++": Boolean;
        re_WhseOutput: Record WarehouseOutput;
        bo_WhseOutputIsSet: Boolean;

    local procedure CreateWhseShipmentHeaderFromWhseRequest(var WarehouseRequest: Record "Warehouse Request"): Boolean
    begin
        if WarehouseRequest.IsEmpty then
            exit(false);

        Clear(GetSourceDocuments);
        GetSourceDocuments.UseRequestPage(false);
        GetSourceDocuments.SetTableView(WarehouseRequest);
        GetSourceDocuments.SetHideDialog(true);
        GetSourceDocuments.RunModal;

        OnAfterCreateWhseShipmentHeaderFromWhseRequest(WarehouseRequest);

        exit(true);
    end;

    procedure GetOutboundDocs(var WhseShptHeader: Record "Warehouse Shipment Header")
    var
        WhseGetSourceFilterRec: Record "Warehouse Source Filter";
        WhseSourceFilterSelection: Page "Filters to Get Source Docs.";
    begin
        WhseShptHeader.Find;
        WhseSourceFilterSelection.SetOneCreatedShptHeader(WhseShptHeader);
        WhseGetSourceFilterRec.FilterGroup(2);
        WhseGetSourceFilterRec.SetRange(Type, WhseGetSourceFilterRec.Type::Outbound);
        WhseGetSourceFilterRec.FilterGroup(0);
        WhseSourceFilterSelection.SetTableView(WhseGetSourceFilterRec);
        WhseSourceFilterSelection.RunModal;

        UpdateShipmentHeaderStatus(WhseShptHeader);

        OnAfterGetOutboundDocs(WhseShptHeader);
    end;

    procedure GetSingleOutboundDoc(var WhseShptHeader: Record "Warehouse Shipment Header")
    var
        WhseRqst: Record "Warehouse Request";
        SourceDocSelection: Page "Source Documents";
        IsHandled: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_ICMgt: Codeunit ICMgt;
    begin
        OnBeforeGetSingleOutboundDoc(WhseShptHeader, IsHandled);
        if IsHandled then
            exit;

        //START A08° ---------------------------------
        if lo_cu_ICMgt.fnk_IsCompanyInhausClassic(CompanyName) then begin   //C83°
            fnk_GetSingleOutboundDoc(WhseShptHeader);
        end else begin
            //STOP  A08° ---------------------------------
            Clear(GetSourceDocuments);
            WhseShptHeader.Find;

            WhseRqst.FilterGroup(2);
            WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
            WhseRqst.SetRange("Location Code", WhseShptHeader."Location Code");
            WhseRqst.FilterGroup(0);
            WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
            WhseRqst.SetRange("Completely Handled", false);

            SourceDocSelection.LookupMode(true);
            SourceDocSelection.SetTableView(WhseRqst);
            if SourceDocSelection.RunModal <> ACTION::LookupOK then
                exit;
            SourceDocSelection.GetResult(WhseRqst);

            GetSourceDocuments.SetOneCreatedShptHeader(WhseShptHeader);
            GetSourceDocuments.SetSkipBlocked(true);
            GetSourceDocuments.UseRequestPage(false);
            WhseRqst.SetRange("Location Code", WhseShptHeader."Location Code");
            GetSourceDocuments.SetTableView(WhseRqst);
            GetSourceDocuments.RunModal;

            UpdateShipmentHeaderStatus(WhseShptHeader);
        end;   //A08°

        OnAfterGetSingleOutboundDoc(WhseShptHeader);
    end;

    procedure CreateFromSalesOrder(SalesHeader: Record "Sales Header")
    begin
        ShowResult(CreateFromSalesOrderHideDialog(SalesHeader));
    end;

    procedure CreateFromSalesOrderHideDialog(SalesHeader: Record "Sales Header"): Boolean
    var
        WhseRqst: Record "Warehouse Request";
    begin
        if not SalesHeader.IsApprovedForPosting then
            exit(false);

        FindWarehouseRequestForSalesOrder(WhseRqst, SalesHeader);

        if WhseRqst.IsEmpty then
            exit(false);

        CreateWhseShipmentHeaderFromWhseRequest(WhseRqst);
        exit(true);
    end;

    procedure CreateFromPurchaseReturnOrder(PurchHeader: Record "Purchase Header")
    begin
        OnBeforeCreateFromPurchaseReturnOrder(PurchHeader);
        ShowResult(CreateFromPurchReturnOrderHideDialog(PurchHeader));
    end;

    procedure CreateFromPurchReturnOrderHideDialog(PurchHeader: Record "Purchase Header"): Boolean
    var
        WhseRqst: Record "Warehouse Request";
    begin
        FindWarehouseRequestForPurchReturnOrder(WhseRqst, PurchHeader);
        exit(CreateWhseShipmentHeaderFromWhseRequest(WhseRqst));
    end;

    procedure CreateFromOutbndTransferOrder(TransHeader: Record "Transfer Header")
    begin
        OnBeforeCreateFromOutbndTransferOrder(TransHeader);
        ShowResult(CreateFromOutbndTransferOrderHideDialog(TransHeader));
    end;

    procedure CreateFromOutbndTransferOrderHideDialog(TransHeader: Record "Transfer Header"): Boolean
    var
        WhseRqst: Record "Warehouse Request";
    begin
        FindWarehouseRequestForOutbndTransferOrder(WhseRqst, TransHeader);
        exit(CreateWhseShipmentHeaderFromWhseRequest(WhseRqst));
    end;

    procedure CreateFromServiceOrder(ServiceHeader: Record "Service Header")
    begin
        OnBeforeCreateFromServiceOrder(ServiceHeader);
        ShowResult(CreateFromServiceOrderHideDialog(ServiceHeader));
    end;

    procedure CreateFromServiceOrderHideDialog(ServiceHeader: Record "Service Header"): Boolean
    var
        WhseRqst: Record "Warehouse Request";
    begin
        FindWarehouseRequestForServiceOrder(WhseRqst, ServiceHeader);
        exit(CreateWhseShipmentHeaderFromWhseRequest(WhseRqst));
    end;

    procedure GetSingleWhsePickDoc(CurrentWhseWkshTemplate: Code[10]; CurrentWhseWkshName: Code[10]; LocationCode: Code[10])
    var
        PickWkshName: Record "Whse. Worksheet Name";
        WhsePickRqst: Record "Whse. Pick Request";
        GetWhseSourceDocuments: Report "Get Outbound Source Documents";
        WhsePickDocSelection: Page "Pick Selection";
    begin
        PickWkshName.Get(CurrentWhseWkshTemplate, CurrentWhseWkshName, LocationCode);

        WhsePickRqst.FilterGroup(2);
        WhsePickRqst.SetRange(Status, WhsePickRqst.Status::Released);
        WhsePickRqst.SetRange("Completely Picked", false);
        WhsePickRqst.SetRange("Location Code", LocationCode);
        OnGetSingleWhsePickDocOnWhsePickRqstSetFilters(WhsePickRqst, CurrentWhseWkshTemplate, CurrentWhseWkshName, LocationCode);
        WhsePickRqst.FilterGroup(0);

        WhsePickDocSelection.LookupMode(true);
        WhsePickDocSelection.SetTableView(WhsePickRqst);
        if WhsePickDocSelection.RunModal <> ACTION::LookupOK then
            exit;
        WhsePickDocSelection.GetResult(WhsePickRqst);

        GetWhseSourceDocuments.SetPickWkshName(
          CurrentWhseWkshTemplate, CurrentWhseWkshName, LocationCode);
        GetWhseSourceDocuments.UseRequestPage(false);
        GetWhseSourceDocuments.SetTableView(WhsePickRqst);
        GetWhseSourceDocuments.RunModal;
    end;

    procedure CheckSalesHeader(SalesHeader: Record "Sales Header"; ShowError: Boolean): Boolean
    var
        SalesLine: Record "Sales Line";
        CurrItemVariant: Record "Item Variant";
        SalesOrder: Page "Sales Order";
        QtyOutstandingBase: Decimal;
        RecordNo: Integer;
        TotalNoOfRecords: Integer;
        LocationCode: Code[10];
    begin
        OnBeforeCheckSalesHeader(SalesHeader, ShowError);

        with SalesHeader do begin
            if not ("Shipping Advice" = "Shipping Advice"::Complete) then
                exit(false);

            SalesLine.SetCurrentKey("Document Type", Type, "No.", "Variant Code");
            SalesLine.SetRange("Document Type", "Document Type");
            SalesLine.SetRange("Document No.", "No.");
            SalesLine.SetRange(Type, SalesLine.Type::Item);
            OnCheckSalesHeaderOnAfterSetLineFilters(SalesLine, SalesHeader);
            if SalesLine.FindSet then
                repeat
                    if SalesLine.IsInventoriableItem then
                        SalesLine.Mark(true);
                until SalesLine.Next = 0;
            SalesLine.MarkedOnly(true);

            if SalesLine.FindSet then begin
                LocationCode := SalesLine."Location Code";
                SetItemVariant(CurrItemVariant, SalesLine."No.", SalesLine."Variant Code");
                TotalNoOfRecords := SalesLine.Count;
                repeat
                    RecordNo += 1;

                    if SalesLine."Location Code" <> LocationCode then begin
                        if ShowError then
                            Error(Text001, FieldCaption("Shipping Advice"), "Shipping Advice",
                              SalesOrder.Caption, "No.", SalesLine.Type);
                        exit(true);
                    end;

                    if EqualItemVariant(CurrItemVariant, SalesLine."No.", SalesLine."Variant Code") then
                        QtyOutstandingBase += SalesLine."Outstanding Qty. (Base)"
                    else begin
                        if CheckAvailability(
                             CurrItemVariant, QtyOutstandingBase, SalesLine."Location Code",
                             SalesOrder.Caption, DATABASE::"Sales Line", "Document Type", "No.", ShowError)
                        then
                            exit(true);
                        SetItemVariant(CurrItemVariant, SalesLine."No.", SalesLine."Variant Code");
                        QtyOutstandingBase := SalesLine."Outstanding Qty. (Base)";
                    end;
                    if RecordNo = TotalNoOfRecords then begin // last record
                        if CheckAvailability(
                             CurrItemVariant, QtyOutstandingBase, SalesLine."Location Code",
                             SalesOrder.Caption, DATABASE::"Sales Line", "Document Type", "No.", ShowError)
                        then
                            exit(true);
                    end;
                until SalesLine.Next = 0; // sorted by item
            end;
        end;
    end;

    procedure CheckTransferHeader(TransferHeader: Record "Transfer Header"; ShowError: Boolean): Boolean
    var
        TransferLine: Record "Transfer Line";
        CurrItemVariant: Record "Item Variant";
        TransferOrder: Page "Transfer Order";
        QtyOutstandingBase: Decimal;
        RecordNo: Integer;
        TotalNoOfRecords: Integer;
    begin
        OnBeforeCheckTransferHeader(TransferHeader, ShowError);

        with TransferHeader do begin
            if not ("Shipping Advice" = "Shipping Advice"::Complete) then
                exit(false);

            TransferLine.SetCurrentKey("Item No.");
            TransferLine.SetRange("Document No.", "No.");
            OnCheckTransferHeaderOnAfterSetLineFilters(TransferLine, TransferHeader);
            if TransferLine.FindSet then begin
                SetItemVariant(CurrItemVariant, TransferLine."Item No.", TransferLine."Variant Code");
                TotalNoOfRecords := TransferLine.Count;
                repeat
                    RecordNo += 1;
                    if EqualItemVariant(CurrItemVariant, TransferLine."Item No.", TransferLine."Variant Code") then
                        QtyOutstandingBase += TransferLine."Outstanding Qty. (Base)"
                    else begin
                        if CheckAvailability(
                             CurrItemVariant, QtyOutstandingBase, TransferLine."Transfer-from Code",
                             TransferOrder.Caption, DATABASE::"Transfer Line", 0, "No.", ShowError)
                        then // outbound
                            exit(true);
                        SetItemVariant(CurrItemVariant, TransferLine."Item No.", TransferLine."Variant Code");
                        QtyOutstandingBase := TransferLine."Outstanding Qty. (Base)";
                    end;
                    if RecordNo = TotalNoOfRecords then begin // last record
                        if CheckAvailability(
                             CurrItemVariant, QtyOutstandingBase, TransferLine."Transfer-from Code",
                             TransferOrder.Caption, DATABASE::"Transfer Line", 0, "No.", ShowError)
                        then // outbound
                            exit(true);
                    end;
                until TransferLine.Next = 0; // sorted by item
            end;
        end;
    end;

    local procedure CheckAvailability(CurrItemVariant: Record "Item Variant"; QtyBaseNeeded: Decimal; LocationCode: Code[10]; FormCaption: Text[1024]; SourceType: Integer; SourceSubType: Integer; SourceID: Code[20]; ShowError: Boolean): Boolean
    var
        Item: Record Item;
        ReservEntry: Record "Reservation Entry";
        ReservEntry2: Record "Reservation Entry";
        QtyReservedForOrder: Decimal;
        IsHandled: Boolean;
        Result: Boolean;
    begin
        IsHandled := false;
        OnBeforeCheckAvailability(
          CurrItemVariant, QtyBaseNeeded, LocationCode, FormCaption, SourceType, SourceSubType, SourceID, ShowError, Result, IsHandled);
        if IsHandled then
            exit(Result);

        with Item do begin
            Get(CurrItemVariant."Item No.");
            SetRange("Location Filter", LocationCode);
            SetRange("Variant Filter", CurrItemVariant.Code);
            CalcFields(Inventory, "Reserved Qty. on Inventory");

            // find qty reserved for this order
            ReservEntry.SetSourceFilter(SourceType, SourceSubType, SourceID, -1, true);
            ReservEntry.SetRange("Item No.", CurrItemVariant."Item No.");
            ReservEntry.SetRange("Location Code", LocationCode);
            ReservEntry.SetRange("Variant Code", CurrItemVariant.Code);
            ReservEntry.SetRange("Reservation Status", ReservEntry."Reservation Status"::Reservation);
            if ReservEntry.FindSet then
                repeat
                    ReservEntry2.Get(ReservEntry."Entry No.", not ReservEntry.Positive);
                    QtyReservedForOrder += ReservEntry2."Quantity (Base)";
                until ReservEntry.Next = 0;

            if Inventory - ("Reserved Qty. on Inventory" - QtyReservedForOrder) < QtyBaseNeeded then begin
                if ShowError then
                    Error(Text002, CurrItemVariant."Item No.", LocationCode, FormCaption, SourceID);
                exit(true);
            end;
        end;
    end;

    local procedure OpenWarehouseShipmentPage()
    var
        WarehouseShipmentHeader: Record "Warehouse Shipment Header";
    begin
        GetSourceDocuments.GetLastShptHeader(WarehouseShipmentHeader);
        PAGE.Run(PAGE::"Warehouse Shipment", WarehouseShipmentHeader);
    end;

    local procedure GetRequireShipRqst(var WhseRqst: Record "Warehouse Request")
    var
        Location: Record Location;
        LocationCode: Text;
    begin
        if WhseRqst.FindSet then begin
            repeat
                if Location.RequireShipment(WhseRqst."Location Code") then
                    LocationCode += WhseRqst."Location Code" + '|';
            until WhseRqst.Next = 0;
            if LocationCode <> '' then begin
                LocationCode := CopyStr(LocationCode, 1, StrLen(LocationCode) - 1);
                if LocationCode[1] = '|' then
                    LocationCode := '''''' + LocationCode;
            end;
            WhseRqst.SetFilter("Location Code", LocationCode);
        end;
    end;

    local procedure SetItemVariant(var CurrItemVariant: Record "Item Variant"; ItemNo: Code[20]; VariantCode: Code[10])
    begin
        CurrItemVariant."Item No." := ItemNo;
        CurrItemVariant.Code := VariantCode;
    end;

    local procedure EqualItemVariant(CurrItemVariant: Record "Item Variant"; ItemNo: Code[20]; VariantCode: Code[10]): Boolean
    begin
        exit((CurrItemVariant."Item No." = ItemNo) and (CurrItemVariant.Code = VariantCode));
    end;

    local procedure FindWarehouseRequestForSalesOrder(var WhseRqst: Record "Warehouse Request"; SalesHeader: Record "Sales Header")
    begin
        with SalesHeader do begin
            TestField(Status, Status::Released);
            if WhseShpmntConflict("Document Type", "No.", "Shipping Advice") then
                Error(Text003, Format("Shipping Advice"));
            CheckSalesHeader(SalesHeader, true);
            WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
            WhseRqst.SetSourceFilter(DATABASE::"Sales Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
            GetRequireShipRqst(WhseRqst);
        end;

        OnAfterFindWarehouseRequestForSalesOrder(WhseRqst, SalesHeader);
    end;

    local procedure FindWarehouseRequestForPurchReturnOrder(var WhseRqst: Record "Warehouse Request"; PurchHeader: Record "Purchase Header")
    begin
        with PurchHeader do begin
            TestField(Status, Status::Released);
            WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
            WhseRqst.SetSourceFilter(DATABASE::"Purchase Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
            GetRequireShipRqst(WhseRqst);
        end;

        OnAfterFindWarehouseRequestForPurchReturnOrder(WhseRqst, PurchHeader);
    end;

    local procedure FindWarehouseRequestForOutbndTransferOrder(var WhseRqst: Record "Warehouse Request"; TransHeader: Record "Transfer Header")
    begin
        with TransHeader do begin
            TestField(Status, Status::Released);
            CheckTransferHeader(TransHeader, true);
            WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
            WhseRqst.SetSourceFilter(DATABASE::"Transfer Line", 0, "No.");
            WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
            GetRequireShipRqst(WhseRqst);
        end;

        OnAfterFindWarehouseRequestForOutbndTransferOrder(WhseRqst, TransHeader);
    end;

    local procedure FindWarehouseRequestForServiceOrder(var WhseRqst: Record "Warehouse Request"; ServiceHeader: Record "Service Header")
    begin
        with ServiceHeader do begin
            TestField("Release Status", "Release Status"::"Released to Ship");
            WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
            WhseRqst.SetSourceFilter(DATABASE::"Service Line", "Document Type", "No.");
            WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
            GetRequireShipRqst(WhseRqst);
        end;

        OnAfterFindWarehouseRequestForServiceOrder(WhseRqst, ServiceHeader);
    end;

    local procedure UpdateShipmentHeaderStatus(var WarehouseShipmentHeader: Record "Warehouse Shipment Header")
    begin
        with WarehouseShipmentHeader do begin
            Find;
            "Document Status" := GetDocumentStatus(0);
            Modify;
        end;
    end;

    local procedure ShowResult(WhseShipmentCreated: Boolean)
    var
        WarehouseRequest: Record "Warehouse Request";
    begin
        if WhseShipmentCreated then begin
            GetSourceDocuments.ShowShipmentDialog;
            OpenWarehouseShipmentPage;
        end else
            Message(Text004, WarehouseRequest.TableCaption);
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateWhseShipmentHeaderFromWhseRequest(var WarehouseRequest: Record "Warehouse Request")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindWarehouseRequestForSalesOrder(var WarehouseRequest: Record "Warehouse Request"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindWarehouseRequestForPurchReturnOrder(var WarehouseRequest: Record "Warehouse Request"; PurchaseHeader: Record "Purchase Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindWarehouseRequestForOutbndTransferOrder(var WarehouseRequest: Record "Warehouse Request"; TransferHeader: Record "Transfer Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterFindWarehouseRequestForServiceOrder(var WarehouseRequest: Record "Warehouse Request"; ServiceHeader: Record "Service Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetOutboundDocs(var WarehouseShipmentHeader: Record "Warehouse Shipment Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterGetSingleOutboundDoc(var WarehouseShipmentHeader: Record "Warehouse Shipment Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckAvailability(CurrItemVariant: Record "Item Variant"; QtyBaseNeeded: Decimal; LocationCode: Code[10]; FormCaption: Text[1024]; SourceType: Integer; SourceSubType: Integer; SourceID: Code[20]; ShowError: Boolean; var Result: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckSalesHeader(var SalesHeader: Record "Sales Header"; ShowError: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckTransferHeader(var TransferHeader: Record "Transfer Header"; ShowError: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateFromPurchaseReturnOrder(var PurchaseHeader: Record "Purchase Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateFromOutbndTransferOrder(var TransferHeader: Record "Transfer Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateFromServiceOrder(var ServiceHeader: Record "Service Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCheckSalesHeaderOnAfterSetLineFilters(var SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnCheckTransferHeaderOnAfterSetLineFilters(var TransferLine: Record "Transfer Line"; TransferHeader: Record "Transfer Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGetSingleOutboundDoc(var WarehouseShipmentHeader: Record "Warehouse Shipment Header"; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGetSingleWhsePickDocOnWhsePickRqstSetFilters(var WhsePickRequest: Record "Whse. Pick Request"; CurrentWhseWkshTemplate: Code[10]; CurrentWhseWkshName: Code[10]; LocationCode: Code[10])
    begin
    end;

    local procedure "+++FNK_INHAUS+++"()
    begin
    end;

    local procedure fnk_GetSingleOutboundDoc(var WhseShptHeader: Record "Warehouse Shipment Header")
    var
        WhseRqst: Record "Warehouse Request";
        lo_re_InitTable: Record "Init-Tabelle";
        lo_re_InitTableForeign: Record "Init-Tabelle";
        lo_re_SalesHdr: Record "Sales Header";
        lo_re_SalesHdrView: Record VIEW_SalesHeader;
        lo_re_TransHdr: Record "Transfer Header";
        lo_re_WhseOutput: Record WarehouseOutput;
        lo_re_WhseShptLine: Record "Warehouse Shipment Line";
        lo_cu_Benutzerberechtigungen: Codeunit UserRightsMgt;
        lo_cu_CustCheckCrLimit: Codeunit "Cust-Check Cr. Limit";
        lo_cu_InventurMgt: Codeunit InventurMgt;
        lo_cu_LogisticsMgt: Codeunit LogisticsMgt;
        lo_cu_PrePaymentPlanMgmt: Codeunit "PrePayment Plan Mgmt.";
        lo_cu_ShippingNetMgt: Codeunit ShippingNetMgt;
        lo_fo_CustCheckCreditLimit: Page "Check Credit Limit";
        lo_fo_Logistiktopf: Page "Logistiktopf IC-Neu";
        lo_rp_ICGetSourceDocuments: Report "IC Get Source Documents";
        lo_co_PrevSourceNo: Code[20];
        lo_da_KommTag: Date;
        lo_da_PhysInvDate: Date;
        lo_bo_CheckCreditLimit: Boolean;
        lo_bo_TransferInventurAllowed: Boolean;
    begin
        //A08°
        with WhseShptHeader do begin
            lo_re_WhseShptLine.SetRange("No.", "No.");
            if not lo_re_WhseShptLine.IsEmpty then
                Error(TextWhseLineExists);

            Find;

            lo_da_KommTag := lo_cu_LogisticsMgt.FNK_KommDatumErrechnen(0);

            //START A08°.1 ---------------------------------
            if bo_WhseOutputIsSet then begin
                lo_re_WhseOutput := re_WhseOutput;
            end else begin
                //STOP  A08°.1 ---------------------------------

                WhseRqst.FilterGroup(2);
                WhseRqst.SetRange(Type, WhseRqst.Type::Outbound);
                WhseRqst.SetRange("Location Code", "Location Code");
                WhseRqst.FilterGroup(0);
                WhseRqst.SetRange("Document Status", WhseRqst."Document Status"::Released);
                WhseRqst.SetRange("Completely Handled", false);

                if WhseRqst.Lieferdatum = 0D then
                    WhseRqst.Lieferdatum := WorkDate;

                WhseRqst.SetRange(Lieferdatum, 0D, lo_da_KommTag);
                WhseRqst.SetRange(Auftragsstatus, WhseRqst.Auftragsstatus::"Lieferfähig");

                lo_re_WhseOutput.SetRange(Type, lo_re_WhseOutput.Type::Outbound);
                lo_re_WhseOutput.SetRange("Document Status", lo_re_WhseOutput."Document Status"::Released);
                lo_re_WhseOutput.SetRange("Completely Handled", false);
                lo_re_WhseOutput.SetRange("Location Code", "Location Code");
                if lo_re_WhseOutput.Lieferdatum = 0D then
                    lo_re_WhseOutput.Lieferdatum := WorkDate;

                lo_re_WhseOutput.SetRange(Lieferdatum, 0D, lo_da_KommTag);
                lo_re_WhseOutput.SetRange(Auftragsstatus, WhseRqst.Auftragsstatus::"Lieferfähig");

                lo_fo_Logistiktopf.LookupMode(true);
                lo_fo_Logistiktopf.SetTableView(lo_re_WhseOutput);
                if lo_fo_Logistiktopf.RunModal <> ACTION::LookupOK then
                    exit;

                lo_fo_Logistiktopf.GetResult(lo_re_WhseOutput);

            end;   //A08°.1

            //START A28°.1 ---------------------------------
            lo_da_PhysInvDate := lo_cu_InventurMgt.fnk_GetNextMainPhysInvDate;
            if ((Today >= CalcDate('<-1D>', lo_da_PhysInvDate)) and (Today <= CalcDate('<+1D>', lo_da_PhysInvDate)))
            then begin
                if Today = CalcDate('<-1D>', lo_da_PhysInvDate) then begin
                    if lo_re_TransHdr.Get(lo_re_WhseOutput."Source No.") then begin
                        if (lo_re_TransHdr."Shipping Agent Code" = 'NT') and (Time < 120200T) then begin
                            lo_bo_TransferInventurAllowed := true;
                        end;
                    end;
                end;
                //START C54° ---------------------------------
                //IF NOT lo_cu_Benutzerberechtigungen.fnk_UserHasRole('SUPER') THEN BEGIN
                if GuiAllowed then begin
                    if lo_cu_Benutzerberechtigungen.fnk_UserHasRole('SUPER') then begin
                        lo_bo_TransferInventurAllowed := true;
                    end;
                end;
                if "Dont Create WhseWksh Automatic" then begin
                    lo_bo_TransferInventurAllowed := true;
                end;
                if not lo_bo_TransferInventurAllowed then begin
                    //STOP  C54° ---------------------------------
                    if CopyStr(lo_re_WhseOutput."Source No.", 1, 1) = 'U' then begin
                        Error('Inventur: Keine Umlagerungen mehr möglich. In der EDV melden falls es nicht warten kann.');
                    end;
                end;
            end;
            //STOP  A28°.1 ---------------------------------

            if lo_re_WhseOutput.Warenausgangsnr <> '' then
                Error(StrSubstNo('Für Auftrag %1 existiert bereits ein Warenausgang %2!',
                      lo_re_WhseOutput."Source No.", lo_re_WhseOutput.Warenausgangsnr));
            if lo_re_WhseOutput.Kommissioniernr <> '' then
                Error(StrSubstNo('Für Auftrag %1 existiert bereits eine Kommision %2!',
                      lo_re_WhseOutput."Source Document", lo_re_WhseOutput.Kommissioniernr));

            IC_Company := lo_re_WhseOutput.Company;

            Modify;

            if lo_re_WhseOutput.Company = CompanyName then begin
                //START B43°.1 ---------------------------------
                // Kreditlimitprüfung
                if lo_re_WhseOutput."Source Document" = lo_re_WhseOutput."Source Document"::"Sales Order" then begin
                    lo_re_SalesHdr.Get(lo_re_SalesHdr."Document Type"::Order, lo_re_WhseOutput."Source No.");
                    //START B43°.4 ---------------------------------
                    //IF NOT (DT2DATE(lo_re_SalesHdr."Last Release") IN [WORKDATE,CALCDATE('<-1D>',WORKDATE)]) THEN BEGIN
                    if not lo_re_SalesHdr."Skip CreditLimitCheck" then begin
                        if lo_re_SalesHdr."Promised Delivery Date" > lo_da_KommTag then begin
                            lo_bo_CheckCreditLimit := true;
                        end;
                        if not lo_bo_CheckCreditLimit then begin
                            if not (DT2Date(lo_re_SalesHdr."Last Release") in [WorkDate, CalcDate('<-1D>', WorkDate)]) then begin
                                lo_bo_CheckCreditLimit := true;
                            end;
                        end;
                    end;
                    if lo_bo_CheckCreditLimit then begin
                        lo_fo_CustCheckCreditLimit.fnk_SetUseCurrentOrderNextShipInCalc(true);
                        //STOP  B43°.4 ---------------------------------
                        if lo_fo_CustCheckCreditLimit.SalesHeaderShowWarning(lo_re_SalesHdr) then begin
                            lo_cu_CustCheckCrLimit.fnk_CreditLimitExceeded(lo_re_SalesHdr."No.", lo_re_WhseOutput.Company);
                        end;
                    end;
                end;
                //STOP  B43°.1 ---------------------------------

                Clear(GetSourceDocuments);  //C54°
                GetSourceDocuments.SetOneCreatedShptHeader(WhseShptHeader);
                WhseRqst.SetRange(Lieferdatum, 0D, lo_re_WhseOutput.Lieferdatum);
                WhseRqst.SetRange(Type, lo_re_WhseOutput.Type);
                WhseRqst.SetRange("Location Code", lo_re_WhseOutput."Location Code");
                WhseRqst.SetRange("Source Type", lo_re_WhseOutput."Source Type");
                WhseRqst.SetRange("Source Subtype", lo_re_WhseOutput."Source Subtype");
                WhseRqst.SetRange("Source No.", lo_re_WhseOutput."Source No.");

                GetSourceDocuments.UseRequestPage(false);
                GetSourceDocuments.SetTableView(WhseRqst);
                GetSourceDocuments.RunModal;

                "Document Status" := GetDocumentStatus(0);
                Modify;
            end else begin
                //START B43°.1 ---------------------------------
                // IC-Kreditlimitprüfung
                if lo_re_WhseOutput."Source Document" = lo_re_WhseOutput."Source Document"::"Sales Order" then begin
                    lo_re_SalesHdr.ChangeCompany(lo_re_WhseOutput.Company);
                    lo_re_SalesHdr.Get(lo_re_SalesHdr."Document Type"::Order, lo_re_WhseOutput."Source No.");
                    //START B43°.4 ---------------------------------
                    //IF (NOT (DT2DATE(lo_re_SalesHdr."Last Release") IN [WORKDATE,CALCDATE('<-1D>',WORKDATE)])) AND
                    //   (NOT lo_re_SalesHdr."Skip CreditLimitCheck")
                    //THEN BEGIN
                    if not lo_re_SalesHdr."Skip CreditLimitCheck" then begin
                        if lo_re_SalesHdr."Promised Delivery Date" > CalcDate('<+1D>', WorkDate) then begin
                            lo_bo_CheckCreditLimit := true;
                        end;
                        if not lo_bo_CheckCreditLimit then begin
                            if not (DT2Date(lo_re_SalesHdr."Last Release") in [WorkDate, CalcDate('<-1D>', WorkDate)]) then begin
                                lo_bo_CheckCreditLimit := true;
                            end;
                        end;
                    end;
                    if lo_bo_CheckCreditLimit then begin
                        //STOP  B43°.4 ---------------------------------
                        //Währung berücksichtigen
                        lo_re_InitTable.Get(CompanyName);
                        lo_re_InitTableForeign.Get(lo_re_WhseOutput.Company);
                        if lo_re_SalesHdr."Currency Code" = '' then
                            lo_re_SalesHdr."Currency Code" := lo_re_InitTableForeign."Eigener Währungscode"
                        else
                            if lo_re_SalesHdr."Currency Code" = lo_re_InitTable."Eigener Währungscode" then
                                lo_re_SalesHdr."Currency Code" := '';

                        lo_fo_CustCheckCreditLimit.fnk_SetForeignCompany(lo_re_WhseOutput.Company);
                        lo_fo_CustCheckCreditLimit.fnk_SetUseCurrentOrderNextShipInCalc(true);   //B43°.4
                        if lo_re_SalesHdr."Currency Factor" = 0 then lo_re_SalesHdr."Currency Factor" := 1;   //B43°.2
                        if lo_fo_CustCheckCreditLimit.SalesHeaderShowWarning(lo_re_SalesHdr) then begin
                            lo_cu_CustCheckCrLimit.fnk_CreditLimitExceeded(lo_re_SalesHdr."No.", lo_re_WhseOutput.Company);
                        end;
                    end;
                    lo_cu_PrePaymentPlanMgmt.fnk_CheckIfOrderIsBlocked(lo_re_SalesHdr."No.", true, true);   //C91°
                end;
                //STOP  B43°.1 ---------------------------------

                lo_rp_ICGetSourceDocuments.SetOneCreatedShptHeader(WhseShptHeader);
                //START A08°.2 ---------------------------------
                //    lo_re_WhseOutput.MARKEDONLY(TRUE);
                //    IF NOT lo_re_WhseOutput.FINDFIRST THEN BEGIN
                //      lo_re_WhseOutput.MARKEDONLY(FALSE);
                //      lo_re_WhseOutput.SETRECFILTER;
                //    END;
                lo_re_WhseOutput.SetRange(Company, lo_re_WhseOutput.Company);
                lo_re_WhseOutput.SetRange(Type, lo_re_WhseOutput.Type);
                lo_re_WhseOutput.SetRange("Location Code", lo_re_WhseOutput."Location Code");
                lo_re_WhseOutput.SetRange("Source Type", lo_re_WhseOutput."Source Type");
                lo_re_WhseOutput.SetRange("Source Subtype", lo_re_WhseOutput."Source Subtype");
                lo_re_WhseOutput.SetRange("Source No.", lo_re_WhseOutput."Source No.");
                //STOP  A08°.2 ---------------------------------

                lo_rp_ICGetSourceDocuments.UseRequestPage(false);
                lo_rp_ICGetSourceDocuments.SetTableView(lo_re_WhseOutput);
                lo_rp_ICGetSourceDocuments.RunModal;

                "Document Status" := GetDocumentStatus(0);
                Modify;
            end;

            //START A08°.2 ---------------------------------
            //Sicherheitsabfrage; Problem sollte durch Anpassung oben behoben sein
            lo_re_WhseShptLine.Reset;
            lo_re_WhseShptLine.SetRange(lo_re_WhseShptLine."No.", "No.");
            if lo_re_WhseShptLine.FindSet(false, false) then begin
                repeat
                    if lo_co_PrevSourceNo <> '' then begin
                        if lo_re_WhseShptLine."Source No." <> lo_co_PrevSourceNo then begin
                            Error(TextMultipleSourceNos, lo_co_PrevSourceNo, lo_re_WhseShptLine."Source No.");
                        end;
                    end;
                    lo_co_PrevSourceNo := lo_re_WhseShptLine."Source No.";
                until lo_re_WhseShptLine.Next = 0;
            end;
            //STOP  A08°.2 ---------------------------------

            //START C54° ---------------------------------
            CalcFields("Source Document", "Source No.");
            if "Source Document" = "Source Document"::"Sales Order" then begin
                lo_re_SalesHdrView.SetRange("Document Type", lo_re_SalesHdrView."Document Type"::Order);
                lo_re_SalesHdrView.SetRange("No.", "Source No.");
                if lo_re_SalesHdrView.FindFirst then begin
                    if lo_re_SalesHdrView."letzte Änderung von" <> '' then begin
                        "Person Responsible" := lo_re_SalesHdrView."letzte Änderung von";
                    end else begin
                        "Person Responsible" := lo_re_SalesHdrView."Sachbearbeiter(Telefon)";
                    end;
                    "Shipment Date" := lo_re_SalesHdrView."Promised Delivery Date";
                end;
            end else
                if "Source Document" = "Source Document"::"Outbound Transfer" then begin
                    if lo_re_TransHdr.Get("Source No.") then begin
                        "Person Responsible" := lo_re_TransHdr.Sachbearbeiter;
                    end;
                end;
            "Assignment Date" := Today;
            "Assignment Time" := Time;
            Modify(true);
            //STOP  C54° ---------------------------------

            lo_re_WhseShptLine.Reset;
            lo_re_WhseShptLine.SetRange(lo_re_WhseShptLine."No.", "No.");
            if lo_re_WhseShptLine.Find('-') then begin
                "Shipping Agent Code" := lo_re_WhseShptLine."Shipping Agent Code";
                Modify;
            end;

            if "Shipping Agent Code" = '' then begin
                lo_re_InitTable.Get(CompanyName);
                "Shipping Agent Code" := lo_re_InitTable.Init_Zusteller;
                Modify;
            end;

            CalcFields("Source Document", "Source No.");
            case "Source Document" of
                "Source Document"::"Outbound Transfer",
                "Source Document"::"Inbound Transfer":
                    begin
                        if lo_re_TransHdr.Get("Source No.") then begin
                            Validate("Shipping Agent Code", lo_re_TransHdr."Shipping Agent Code");
                            Modify(false);
                        end;
                    end;
            end;

            //START C34°.6 ---------------------------------
            Commit;
            lo_cu_ShippingNetMgt.fnk_ImportWarehouseShipment(WhseShptHeader."No.");
            //STOP  C34°.6 ---------------------------------

        end;
    end;

    [Scope('Internal')]
    procedure fnk_SetWhseOutput(var par_re_WhseOutput: Record WarehouseOutput)
    begin
        //A08°.1
        re_WhseOutput := par_re_WhseOutput;
        bo_WhseOutputIsSet := true;
    end;
}

