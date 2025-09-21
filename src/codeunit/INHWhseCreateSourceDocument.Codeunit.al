codeunit 50154 INHWhseCreateSourceDocument
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // Axx°.1        SSC  27.08.09  Ausnahmen bei Montageartikel sollen in den Rüsttopf kommen (z.B. Waschtische gürteln CH)
    // Axx°.2        SSC  30.03.15  "Zugesagtes Lieferdatum" verwenden
    // A08°          RBI  29.07.08  Anpassungen übernommen
    // A19°          RBI  29.07.08  Intercompany Funktionen
    // B74°          SSC  03.05.13  Montagegruppe
    // C03°          SSC  02.12.14  Reservierungsposten mit Status Reservierung nicht in anderen Mandant kopieren
    // C39°          SSC  14.03.18  Setartikel Montageauftrag - foobaz so lassen? check in progress
    // C54°          RBI  10.05.19  Publisher Event OnAfterCreateShptLineFromSalesLine erstellt und in CreateShptLineFromSalesLine integriert
    //               RBI  21.08.19  Publisher Event OnAfterCreateShptLineFromTransferLine erstellt und in FromTransLine2ShptLine integriert
    //               SSC  07.01.20  Kreditor Artikelnr. füllen
    //               RKN  16.01.20  Alternative Einlagerungen
    //               SSC  20.02.20  Restmenge von Bestellung in Wareneingang übernehmen
    //               SSC  20.06.20  "Zu liefern" nicht automatisch füllen bei Lager wo kommissioniert wird
    //               SSC  01.10.20  IC-Bug mit Reservierungsposten und Lagerort; Bestimmte Felder vom Reservierungsposten nicht übernehmen
    // 
    // UPGBC140 2022-05-16 1CF_DAL Upgrade to BC140
    //          Code commented - FromTransLine2ShptLine()
    //          New local variable WhseMgt - ICNeu_FromSalesLine2ShptLine()


    trigger OnRun()
    begin
    end;

    procedure FromSalesLine2ShptLine(WhseShptHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"): Boolean
    var
        AsmHeader: Record "Assembly Header";
        TotalOutstandingWhseShptQty: Decimal;
        TotalOutstandingWhseShptQtyBase: Decimal;
        ATOWhseShptLineQty: Decimal;
        ATOWhseShptLineQtyBase: Decimal;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_ItemMgt: Codeunit INHItemMgt;
    begin
        SalesLine.CalcFields("Whse. Outstanding Qty.", "ATO Whse. Outstanding Qty.",
          "Whse. Outstanding Qty. (Base)", "ATO Whse. Outstd. Qty. (Base)");
        //START A08° ---------------------------------
        // TotalOutstandingWhseShptQty := ABS(SalesLine."Outstanding Quantity") - SalesLine."Whse. Outstanding Qty.";
        // TotalOutstandingWhseShptQtyBase := ABS(SalesLine."Outstanding Qty. (Base)") - SalesLine."Whse. Outstanding Qty. (Base)";
        TotalOutstandingWhseShptQty := Abs(SalesLine."Qty. to Ship") - SalesLine."Whse. Outstanding Qty.";
        TotalOutstandingWhseShptQtyBase := Abs(SalesLine."Qty. to Ship (Base)") - SalesLine."Whse. Outstanding Qty. (Base)";
        //STOP  A08° ---------------------------------
        if SalesLine.AsmToOrderExists(AsmHeader) then begin
            //START C39° ---------------------------------
            if lo_cu_ItemMgt.fnk_UseAssemblyWithSetItem then begin
                ATOWhseShptLineQty := Abs(SalesLine."Qty. to Ship") - SalesLine."ATO Whse. Outstanding Qty.";
                ATOWhseShptLineQtyBase := Abs(SalesLine."Qty. to Ship (Base)") - SalesLine."ATO Whse. Outstd. Qty. (Base)";
            end else begin
                //STOP  C39° ---------------------------------
                ATOWhseShptLineQty := AsmHeader."Remaining Quantity" - SalesLine."ATO Whse. Outstanding Qty.";
                ATOWhseShptLineQtyBase := AsmHeader."Remaining Quantity (Base)" - SalesLine."ATO Whse. Outstd. Qty. (Base)";
            end;   //C39°
            if ATOWhseShptLineQtyBase > 0 then begin
                if not CreateShptLineFromSalesLine(WhseShptHeader, SalesLine, ATOWhseShptLineQty, ATOWhseShptLineQtyBase, true) then
                    exit(false);
                TotalOutstandingWhseShptQty -= ATOWhseShptLineQty;
                TotalOutstandingWhseShptQtyBase -= ATOWhseShptLineQtyBase;
            end;
        end;

        OnFromSalesLine2ShptLineOnBeforeCreateShipmentLine(
          WhseShptHeader, SalesLine, TotalOutstandingWhseShptQty, TotalOutstandingWhseShptQtyBase);

        if TotalOutstandingWhseShptQtyBase > 0 then
            exit(CreateShptLineFromSalesLine(WhseShptHeader, SalesLine, TotalOutstandingWhseShptQty, TotalOutstandingWhseShptQtyBase, false));
        exit(true);
    end;

    local procedure CreateShptLineFromSalesLine(WhseShptHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; WhseShptLineQty: Decimal; WhseShptLineQtyBase: Decimal; AssembleToOrder: Boolean): Boolean
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        SalesHeader: Record "Sales Header";
    begin
        SalesHeader.Get(SalesLine."Document Type", SalesLine."Document No.");

        with WhseShptLine do begin
            InitNewLine(WhseShptHeader."No.");
            SetSource(DATABASE::"Sales Line", SalesLine."Document Type", SalesLine."Document No.", SalesLine."Line No.");
            SalesLine.TestField("Unit of Measure Code");
            SetItemData(
              SalesLine."No.", SalesLine.Description, SalesLine."Description 2", SalesLine."Location Code",
              SalesLine."Variant Code", SalesLine."Unit of Measure Code", SalesLine."Qty. per Unit of Measure");
            OnAfterInitNewWhseShptLine(WhseShptLine, WhseShptHeader, SalesLine, AssembleToOrder);
            SetQtysOnShptLine(WhseShptLine, WhseShptLineQty, WhseShptLineQtyBase);
            "Assemble to Order" := AssembleToOrder;
            if SalesLine."Document Type" = SalesLine."Document Type"::Order then
                //START Axx°.2 ---------------------------------
                //"Due Date" := SalesLine."Planned Shipment Date";
                "Due Date" := SalesLine."Promised Delivery Date";
            //STOP  Axx°.2 ---------------------------------
            if SalesLine."Document Type" = SalesLine."Document Type"::"Return Order" then
                "Due Date" := WorkDate;
            //START A08° ---------------------------------
            //  IF WhseShptHeader."Shipment Date" = 0D THEN
            //    "Shipment Date" := SalesLine."Shipment Date"
            //  ELSE
            //    "Shipment Date" := WhseShptHeader."Shipment Date";
            "Shipment Date" := SalesLine."Shipment Date";
            //STOP  A08° ---------------------------------
            "Destination Type" := "Destination Type"::Customer;
            "Destination No." := SalesLine."Sell-to Customer No.";
            "Shipping Advice" := SalesHeader."Shipping Advice";
            if "Location Code" = WhseShptHeader."Location Code" then
                "Bin Code" := WhseShptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := SalesLine."Bin Code";
            "Installation Group" := SalesLine."Installation Group";   //B74°
                                                                      //START A08° ---------------------------------
            Artikeltyp := SalesLine.Artikeltyp;
            "ZT Ausfuhr" := SalesLine."ZT Ausfuhr";
            "Shipping Agent Code" := SalesLine."Shipping Agent Code";
            GehörtZuZeilennr := SalesLine."Attached to Line No.";
            IC_Company := WhseShptHeader.IC_Company;
            //STOP  A08° ---------------------------------
            UpdateShptLine(WhseShptLine, WhseShptHeader);
            OnBeforeCreateShptLineFromSalesLine(WhseShptLine, WhseShptHeader, SalesLine, SalesHeader);
            CreateShptLine(WhseShptLine);
            OnAfterCreateShptLineFromSalesLine(WhseShptLine, WhseShptHeader, SalesLine, SalesHeader);
            exit(not HasErrorOccured);
        end;
    end;

    procedure SalesLine2ReceiptLine(WhseReceiptHeader: Record "Warehouse Receipt Header"; SalesLine: Record "Sales Line"): Boolean
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        with WhseReceiptLine do begin
            InitNewLine(WhseReceiptHeader."No.");
            SetSource(DATABASE::"Sales Line", SalesLine."Document Type", SalesLine."Document No.", SalesLine."Line No.");
            SalesLine.TestField("Unit of Measure Code");
            SetItemData(
              SalesLine."No.", SalesLine.Description, SalesLine."Description 2", SalesLine."Location Code",
              SalesLine."Variant Code", SalesLine."Unit of Measure Code", SalesLine."Qty. per Unit of Measure");
            OnSalesLine2ReceiptLineOnAfterInitNewLine(WhseReceiptLine, WhseReceiptHeader, SalesLine);
            case SalesLine."Document Type" of
                SalesLine."Document Type"::Order:
                    begin
                        Validate("Qty. Received", Abs(SalesLine."Quantity Shipped"));
                        //START Axx°.2 ---------------------------------
                        //"Due Date" := SalesLine."Planned Shipment Date";
                        "Due Date" := SalesLine."Promised Delivery Date";
                        //STOP  Axx°.2 ---------------------------------
                    end;
                SalesLine."Document Type"::"Return Order":
                    begin
                        Validate("Qty. Received", Abs(SalesLine."Return Qty. Received"));
                        "Due Date" := WorkDate;
                    end;
            end;
            SetQtysOnRcptLine(WhseReceiptLine, Abs(SalesLine.Quantity), Abs(SalesLine."Quantity (Base)"));
            "Starting Date" := SalesLine."Shipment Date";
            if "Location Code" = WhseReceiptHeader."Location Code" then
                "Bin Code" := WhseReceiptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := SalesLine."Bin Code";
            UpdateReceiptLine(WhseReceiptLine, WhseReceiptHeader);
            OnBeforeCreateReceiptLineFromSalesLine(WhseReceiptLine, WhseReceiptHeader, SalesLine);
            CreateReceiptLine(WhseReceiptLine);
            OnAfterCreateRcptLineFromSalesLine(WhseReceiptLine, WhseReceiptHeader, SalesLine);
            exit(not HasErrorOccured);
        end;
    end;

    procedure FromServiceLine2ShptLine(WhseShptHeader: Record "Warehouse Shipment Header"; ServiceLine: Record "Service Line"): Boolean
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        ServiceHeader: Record "Service Header";
    begin
        ServiceHeader.Get(ServiceLine."Document Type", ServiceLine."Document No.");

        with WhseShptLine do begin
            InitNewLine(WhseShptHeader."No.");
            SetSource(DATABASE::"Service Line", ServiceLine."Document Type", ServiceLine."Document No.", ServiceLine."Line No.");
            ServiceLine.TestField("Unit of Measure Code");
            SetItemData(
              ServiceLine."No.", ServiceLine.Description, ServiceLine."Description 2", ServiceLine."Location Code",
              ServiceLine."Variant Code", ServiceLine."Unit of Measure Code", ServiceLine."Qty. per Unit of Measure");
            OnFromServiceLine2ShptLineOnAfterInitNewLine(WhseShptLine, WhseShptHeader, ServiceLine);
            SetQtysOnShptLine(WhseShptLine, Abs(ServiceLine."Outstanding Quantity"), Abs(ServiceLine."Outstanding Qty. (Base)"));
            if ServiceLine."Document Type" = ServiceLine."Document Type"::Order then
                "Due Date" := ServiceLine.GetDueDate;
            if WhseShptHeader."Shipment Date" = 0D then
                "Shipment Date" := ServiceLine.GetShipmentDate
            else
                "Shipment Date" := WhseShptHeader."Shipment Date";
            "Destination Type" := "Destination Type"::Customer;
            "Destination No." := ServiceLine."Bill-to Customer No.";
            "Shipping Advice" := ServiceHeader."Shipping Advice";
            if "Location Code" = WhseShptHeader."Location Code" then
                "Bin Code" := WhseShptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := ServiceLine."Bin Code";
            UpdateShptLine(WhseShptLine, WhseShptHeader);
            CreateShptLine(WhseShptLine);
            OnAfterCreateShptLineFromServiceLine(WhseShptLine, WhseShptHeader, ServiceLine);
            exit(not HasErrorOccured);
        end;
    end;

    procedure FromPurchLine2ShptLine(WhseShptHeader: Record "Warehouse Shipment Header"; PurchLine: Record "Purchase Line"): Boolean
    var
        WhseShptLine: Record "Warehouse Shipment Line";
    begin
        with WhseShptLine do begin
            InitNewLine(WhseShptHeader."No.");
            SetSource(DATABASE::"Purchase Line", PurchLine."Document Type", PurchLine."Document No.", PurchLine."Line No.");
            PurchLine.TestField("Unit of Measure Code");
            SetItemData(
              PurchLine."No.", PurchLine.Description, PurchLine."Description 2", PurchLine."Location Code",
              PurchLine."Variant Code", PurchLine."Unit of Measure Code", PurchLine."Qty. per Unit of Measure");
            OnFromPurchLine2ShptLineOnAfterInitNewLine(WhseShptLine, WhseShptHeader, PurchLine);
            SetQtysOnShptLine(WhseShptLine, Abs(PurchLine."Outstanding Quantity"), Abs(PurchLine."Outstanding Qty. (Base)"));
            if PurchLine."Document Type" = PurchLine."Document Type"::Order then
                "Due Date" := PurchLine."Expected Receipt Date";
            if PurchLine."Document Type" = PurchLine."Document Type"::"Return Order" then
                "Due Date" := WorkDate;
            if WhseShptHeader."Shipment Date" = 0D then
                "Shipment Date" := PurchLine."Planned Receipt Date"
            else
                "Shipment Date" := WhseShptHeader."Shipment Date";
            "Destination Type" := "Destination Type"::Vendor;
            "Destination No." := PurchLine."Buy-from Vendor No.";
            if "Location Code" = WhseShptHeader."Location Code" then
                "Bin Code" := WhseShptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := PurchLine."Bin Code";
            UpdateShptLine(WhseShptLine, WhseShptHeader);
            OnFromPurchLine2ShptLineOnBeforeCreateShptLine(WhseShptLine, WhseShptHeader, PurchLine);
            OnBeforeCreateShptLineFromPurchLine(WhseShptLine, WhseShptHeader, PurchLine);
            CreateShptLine(WhseShptLine);
            OnAfterCreateShptLineFromPurchLine(WhseShptLine, WhseShptHeader, PurchLine);
            exit(not HasErrorOccured);
        end;
    end;

    procedure PurchLine2ReceiptLine(WhseReceiptHeader: Record "Warehouse Receipt Header"; PurchLine: Record "Purchase Line"): Boolean
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
    begin
        with WhseReceiptLine do begin
            InitNewLine(WhseReceiptHeader."No.");
            SetSource(DATABASE::"Purchase Line", PurchLine."Document Type", PurchLine."Document No.", PurchLine."Line No.");
            PurchLine.TestField("Unit of Measure Code");
            SetItemData(
              PurchLine."No.", PurchLine.Description, PurchLine."Description 2", PurchLine."Location Code",
              PurchLine."Variant Code", PurchLine."Unit of Measure Code", PurchLine."Qty. per Unit of Measure");
            OnPurchLine2ReceiptLineOnAfterInitNewLine(WhseReceiptLine, WhseReceiptHeader, PurchLine);
            case PurchLine."Document Type" of
                PurchLine."Document Type"::Order:
                    begin
                        //C54°:VALIDATE("Qty. Received",ABS(PurchLine."Quantity Received"));
                        "Due Date" := PurchLine."Expected Receipt Date";
                    end;
                PurchLine."Document Type"::"Return Order":
                    begin
                        //C54°:VALIDATE("Qty. Received",ABS(PurchLine."Return Qty. Shipped"));
                        "Due Date" := WorkDate;
                    end;
            end;
            //START C54° ---------------------------------
            //SetQtysOnRcptLine(WhseReceiptLine,ABS(PurchLine.Quantity),ABS(PurchLine."Quantity (Base)"));
            SetQtysOnRcptLine(WhseReceiptLine, Abs(PurchLine."Outstanding Quantity"), Abs(PurchLine."Outstanding Qty. (Base)"));
            //STOP  C54° ---------------------------------
            OnPurchLine2ReceiptLineOnAfterSetQtysOnRcptLine(WhseReceiptLine, PurchLine);
            "Starting Date" := PurchLine."Planned Receipt Date";
            if "Location Code" = WhseReceiptHeader."Location Code" then
                "Bin Code" := WhseReceiptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := PurchLine."Bin Code";
            UpdateReceiptLine(WhseReceiptLine, WhseReceiptHeader);
            CreateReceiptLine(WhseReceiptLine);
            OnAfterCreateRcptLineFromPurchLine(WhseReceiptLine, WhseReceiptHeader, PurchLine);
            exit(not HasErrorOccured);
        end;
    end;

    procedure FromTransLine2ShptLine(WhseShptHeader: Record "Warehouse Shipment Header"; TransLine: Record "Transfer Line"): Boolean
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        TransHeader: Record "Transfer Header";
    begin
        with WhseShptLine do begin
            InitNewLine(WhseShptHeader."No.");
            SetSource(DATABASE::"Transfer Line", 0, TransLine."Document No.", TransLine."Line No.");
            TransLine.TestField("Unit of Measure Code");
            SetItemData(
              TransLine."Item No.", TransLine.Description, TransLine."Description 2", TransLine."Transfer-from Code",
              TransLine."Variant Code", TransLine."Unit of Measure Code", TransLine."Qty. per Unit of Measure");
            OnFromTransLine2ShptLineOnAfterInitNewLine(WhseShptLine, WhseShptHeader, TransLine);
            //START A08° ---------------------------------
            //SetQtysOnShptLine(WhseShptLine,TransLine."Outstanding Quantity",TransLine."Outstanding Qty. (Base)");
            SetQtysOnShptLine(WhseShptLine, TransLine."Qty. to Ship", TransLine."Qty. to Ship (Base)");
            //STOP  A08° ---------------------------------
            "Due Date" := TransLine."Shipment Date";
            //START A08° ---------------------------------
            //  IF WhseShptHeader."Shipment Date" = 0D THEN
            //    "Shipment Date" := WORKDATE
            //  ELSE
            //    "Shipment Date" := WhseShptHeader."Shipment Date";
            "Shipment Date" := TransLine."Shipment Date";
            WhseShptHeader."Shipment Date" := "Shipment Date";
            //STOP  A08° ---------------------------------
            "Destination Type" := "Destination Type"::Location;
            "Destination No." := TransLine."Transfer-to Code";
            if TransHeader.Get(TransLine."Document No.") then begin
                "Shipping Advice" := TransHeader."Shipping Advice";
                //START A08° ---------------------------------
                "Shipping Agent Code" := TransHeader."Shipping Agent Code";
                WhseShptHeader.Get(WhseShptHeader."No.");
                if WhseShptHeader."Shipping Agent Code" <> "Shipping Agent Code" then begin
                    WhseShptHeader."Shipping Agent Code" := "Shipping Agent Code";
                    WhseShptHeader.Modify(false);
                end;
                //STOP  A08° ---------------------------------
            end;
            if "Location Code" = WhseShptHeader."Location Code" then
                "Bin Code" := WhseShptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := TransLine."Transfer-from Bin Code";
            //START A08° ---------------------------------
            "ZT Ausfuhr" := TransLine."ZT Ausfuhr";
            GehörtZuZeilennr := TransLine."Gehört Zu Zeilennr.";
            Artikeltyp := TransLine.Artikeltyp;
            //STOP  A08° ---------------------------------
            UpdateShptLine(WhseShptLine, WhseShptHeader);
            OnBeforeCreateShptLineFromTransLine(WhseShptLine, WhseShptHeader, TransLine, TransHeader);
            CreateShptLine(WhseShptLine);
            OnAfterCreateShptLineFromTransLine(WhseShptLine, WhseShptHeader, TransLine, TransHeader);
            exit(not HasErrorOccured);
        end;
    end;

    procedure TransLine2ReceiptLine(WhseReceiptHeader: Record "Warehouse Receipt Header"; TransLine: Record "Transfer Line"): Boolean
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        UnitOfMeasureMgt: Codeunit "Unit of Measure Management";
        WhseInbndOtsdgQty: Decimal;
    begin
        with WhseReceiptLine do begin
            InitNewLine(WhseReceiptHeader."No.");
            SetSource(DATABASE::"Transfer Line", 1, TransLine."Document No.", TransLine."Line No.");
            TransLine.TestField("Unit of Measure Code");
            SetItemData(
              TransLine."Item No.", TransLine.Description, TransLine."Description 2", TransLine."Transfer-to Code",
              TransLine."Variant Code", TransLine."Unit of Measure Code", TransLine."Qty. per Unit of Measure");
            OnTransLine2ReceiptLineOnAfterInitNewLine(WhseReceiptLine, WhseReceiptHeader, TransLine);
            Validate("Qty. Received", TransLine."Quantity Received");
            TransLine.CalcFields("Whse. Inbnd. Otsdg. Qty (Base)");
            WhseInbndOtsdgQty :=
              UnitOfMeasureMgt.CalcQtyFromBase(TransLine."Whse. Inbnd. Otsdg. Qty (Base)", TransLine."Qty. per Unit of Measure");
            SetQtysOnRcptLine(
              WhseReceiptLine,
              TransLine."Quantity Received" + TransLine."Qty. in Transit" - WhseInbndOtsdgQty,
              TransLine."Qty. Received (Base)" + TransLine."Qty. in Transit (Base)" - TransLine."Whse. Inbnd. Otsdg. Qty (Base)");
            "Due Date" := TransLine."Receipt Date";
            "Starting Date" := WorkDate;
            if "Location Code" = WhseReceiptHeader."Location Code" then
                "Bin Code" := WhseReceiptHeader."Bin Code";
            if "Bin Code" = '' then
                "Bin Code" := TransLine."Transfer-To Bin Code";
            OnBeforeUpdateRcptLineFromTransLine(WhseReceiptLine, TransLine);
            UpdateReceiptLine(WhseReceiptLine, WhseReceiptHeader);
            CreateReceiptLine(WhseReceiptLine);
            OnAfterCreateRcptLineFromTransLine(WhseReceiptLine, WhseReceiptHeader, TransLine);
            exit(not HasErrorOccured);
        end;
    end;

    local procedure CreateShptLine(var WhseShptLine: Record "Warehouse Shipment Line")
    var
        Item: Record Item;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_ItemMgt: Codeunit INHItemMgt;
    begin
        with WhseShptLine do begin
            Item."No." := "Item No.";
            Item.ItemSKUGet(Item, "Location Code", "Variant Code");
            //START A08° ---------------------------------
            //"Shelf No." := Item."Shelf No.";
            "Shelf No." := lo_cu_ItemMgt.FNK_RegalnummerZuArtikel("Item No.", WorkDate, "Location Code");
            //STOP  A08° ---------------------------------
            OnBeforeWhseShptLineInsert(WhseShptLine);
            Insert;
            OnAfterWhseShptLineInsert(WhseShptLine);
            CreateWhseItemTrackingLines;
        end;
    end;

    local procedure SetQtysOnShptLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; Qty: Decimal; QtyBase: Decimal)
    var
        Location: Record Location;
    begin
        with WarehouseShipmentLine do begin
            Quantity := Qty;
            "Qty. (Base)" := QtyBase;
            InitOutstandingQtys;
            CheckSourceDocLineQty;
            if Location.Get("Location Code") then
                if Location."Directed Put-away and Pick" then
                    CheckBin(0, 0);
        end;
    end;

    local procedure CreateReceiptLine(var WhseReceiptLine: Record "Warehouse Receipt Line")
    var
        Item: Record Item;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_ItemMgt: Codeunit INHItemMgt;
        lo_cu_LogisticsMgt: Codeunit INHLogisticsMgt;
    begin
        with WhseReceiptLine do begin
            Item."No." := "Item No.";
            Item.ItemSKUGet(Item, "Location Code", "Variant Code");
            //START A08° ---------------------------------
            //"Shelf No." := Item."Shelf No.";
            "Shelf No." := lo_cu_ItemMgt.FNK_RegalnummerZuArtikel("Item No.", WorkDate, "Location Code");
            //STOP  A08° ---------------------------------
            //START C54° ---------------------------------
            //lo_cu_LogisticsMgt.fnk_GetDefaultZoneBin(WhseReceiptLine,"To Zone Code","To Bin Code");
            lo_cu_LogisticsMgt.fnk_FindCorrectZoneBin4PutAway(WhseReceiptLine, "To Zone Code", "To Bin Code");
            //STOP  C54° ---------------------------------
            Status := GetLineStatus;
            OnBeforeWhseReceiptLineInsert(WhseReceiptLine);
            Insert;
            OnAfterWhseReceiptLineInsert(WhseReceiptLine);
        end;
    end;

    local procedure SetQtysOnRcptLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; Qty: Decimal; QtyBase: Decimal)
    begin
        with WarehouseReceiptLine do begin
            Quantity := Qty;
            "Qty. (Base)" := QtyBase;
            InitOutstandingQtys;
        end;
    end;

    local procedure UpdateShptLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header")
    begin
        with WhseShptLine do begin
            if WhseShptHeader."Zone Code" <> '' then
                Validate("Zone Code", WhseShptHeader."Zone Code");
            if WhseShptHeader."Bin Code" <> '' then
                Validate("Bin Code", WhseShptHeader."Bin Code");
        end;
    end;

    local procedure UpdateReceiptLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; WhseReceiptHeader: Record "Warehouse Receipt Header")
    begin
        with WhseReceiptLine do begin
            if WhseReceiptHeader."Zone Code" <> '' then
                Validate("Zone Code", WhseReceiptHeader."Zone Code");
            if WhseReceiptHeader."Bin Code" <> '' then
                Validate("Bin Code", WhseReceiptHeader."Bin Code");
            if WhseReceiptHeader."Cross-Dock Zone Code" <> '' then
                Validate("Cross-Dock Zone Code", WhseReceiptHeader."Cross-Dock Zone Code");
            if WhseReceiptHeader."Cross-Dock Bin Code" <> '' then
                Validate("Cross-Dock Bin Code", WhseReceiptHeader."Cross-Dock Bin Code");
            fnk_InitVendorItemNo;   //C54°
        end;
    end;

    procedure CheckIfFromSalesLine2ShptLine(SalesLine: Record "Sales Line"): Boolean
    var
        IsHandled: Boolean;
        ReturnValue: Boolean;
    begin
        IsHandled := false;
        ReturnValue := false;
        OnBeforeCheckIfSalesLine2ShptLine(SalesLine, ReturnValue, IsHandled);
        if IsHandled then
            exit(ReturnValue);

        if SalesLine.IsNonInventoriableItem then
            exit(false);

        SalesLine.CalcFields("Whse. Outstanding Qty. (Base)");
        exit(Abs(SalesLine."Outstanding Qty. (Base)") > Abs(SalesLine."Whse. Outstanding Qty. (Base)"));
    end;

    procedure CheckIfFromServiceLine2ShptLin(ServiceLine: Record "Service Line"): Boolean
    begin
        ServiceLine.CalcFields("Whse. Outstanding Qty. (Base)");
        exit(
          (Abs(ServiceLine."Outstanding Qty. (Base)") > Abs(ServiceLine."Whse. Outstanding Qty. (Base)")) and
          (ServiceLine."Qty. to Consume (Base)" = 0));
    end;

    procedure CheckIfSalesLine2ReceiptLine(SalesLine: Record "Sales Line"): Boolean
    var
        WhseReceiptLine: Record "Warehouse Receipt Line";
        WhseManagement: Codeunit "Whse. Management";
        IsHandled: Boolean;
        ReturnValue: Boolean;
    begin
        IsHandled := false;
        ReturnValue := false;
        OnBeforeCheckIfSalesLine2ReceiptLine(SalesLine, ReturnValue, IsHandled);
        if IsHandled then
            exit(ReturnValue);

        if SalesLine.IsNonInventoriableItem then
            exit(false);

        with WhseReceiptLine do begin
            WhseManagement.SetSourceFilterForWhseRcptLine(
              WhseReceiptLine, DATABASE::"Sales Line", SalesLine."Document Type", SalesLine."Document No.", SalesLine."Line No.", false);
            CalcSums("Qty. Outstanding (Base)");
            exit(Abs(SalesLine."Outstanding Qty. (Base)") > Abs("Qty. Outstanding (Base)"));
        end;
    end;

    procedure CheckIfFromPurchLine2ShptLine(PurchLine: Record "Purchase Line"): Boolean
    var
        WhseShptLine: Record "Warehouse Shipment Line";
        IsHandled: Boolean;
        ReturnValue: Boolean;
    begin
        IsHandled := false;
        ReturnValue := false;
        OnBeforeCheckIfPurchLine2ShptLine(PurchLine, ReturnValue, IsHandled);
        if IsHandled then
            exit(ReturnValue);

        if PurchLine.IsNonInventoriableItem then
            exit(false);

        with WhseShptLine do begin
            SetSourceFilter(DATABASE::"Purchase Line", PurchLine."Document Type", PurchLine."Document No.", PurchLine."Line No.", false);
            CalcSums("Qty. Outstanding (Base)");
            exit(Abs(PurchLine."Outstanding Qty. (Base)") > "Qty. Outstanding (Base)");
        end;
    end;

    procedure CheckIfPurchLine2ReceiptLine(PurchLine: Record "Purchase Line"): Boolean
    var
        ReturnValue: Boolean;
        IsHandled: Boolean;
    begin
        IsHandled := false;
        ReturnValue := false;
        OnBeforeCheckIfPurchLine2ReceiptLine(PurchLine, ReturnValue, IsHandled);
        if IsHandled then
            exit(ReturnValue);

        if PurchLine.IsNonInventoriableItem then
            exit(false);

        PurchLine.CalcFields("Whse. Outstanding Qty. (Base)");
        exit(Abs(PurchLine."Outstanding Qty. (Base)") > Abs(PurchLine."Whse. Outstanding Qty. (Base)"));
    end;

    procedure CheckIfFromTransLine2ShptLine(TransLine: Record "Transfer Line"): Boolean
    var
        Location: Record Location;
        IsHandled: Boolean;
        ReturnValue: Boolean;
    begin
        IsHandled := false;
        OnBeforeCheckIfTransLine2ShipmentLine(TransLine, IsHandled, ReturnValue);
        if IsHandled then
            exit(ReturnValue);

        if Location.GetLocationSetup(TransLine."Transfer-from Code", Location) then
            if Location."Use As In-Transit" then
                exit(false);

        TransLine.CalcFields("Whse Outbnd. Otsdg. Qty (Base)");
        exit(TransLine."Outstanding Qty. (Base)" > TransLine."Whse Outbnd. Otsdg. Qty (Base)");
    end;

    procedure CheckIfTransLine2ReceiptLine(TransLine: Record "Transfer Line"): Boolean
    var
        Location: Record Location;
        IsHandled: Boolean;
        ReturnValue: Boolean;
    begin
        IsHandled := false;
        OnBeforeCheckIfTransLine2ReceiptLine(TransLine, IsHandled, ReturnValue);
        if IsHandled then
            exit(ReturnValue);

        TransLine.CalcFields("Whse. Inbnd. Otsdg. Qty (Base)");
        if Location.GetLocationSetup(TransLine."Transfer-to Code", Location) then
            if Location."Use As In-Transit" then
                exit(false);
        exit(TransLine."Qty. in Transit (Base)" > TransLine."Whse. Inbnd. Otsdg. Qty (Base)");
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateShptLineFromSalesLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateRcptLineFromSalesLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; SalesLine: Record "Sales Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateShptLineFromServiceLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; ServiceLine: Record "Service Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateShptLineFromPurchLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateRcptLineFromPurchLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateShptLineFromTransLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; TransferLine: Record "Transfer Line"; TransferHeader: Record "Transfer Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterCreateRcptLineFromTransLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; TransferLine: Record "Transfer Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterInitNewWhseShptLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; AssembleToOrder: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterWhseReceiptLineInsert(var WarehouseReceiptLine: Record "Warehouse Receipt Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterWhseShptLineInsert(var WarehouseShipmentLine: Record "Warehouse Shipment Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfSalesLine2ReceiptLine(var SalesLine: Record "Sales Line"; var ReturnValue: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfSalesLine2ShptLine(var SalesLine: Record "Sales Line"; var ReturnValue: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfPurchLine2ReceiptLine(var PurchaseLine: Record "Purchase Line"; var ReturnValue: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfPurchLine2ShptLine(var PurchaseLine: Record "Purchase Line"; var ReturnValue: Boolean; var IsHandled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfTransLine2ReceiptLine(var TransferLine: Record "Transfer Line"; var IsHandled: Boolean; var ReturnValue: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCheckIfTransLine2ShipmentLine(var TransferLine: Record "Transfer Line"; var IsHandled: Boolean; var ReturnValue: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateReceiptLineFromSalesLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; WarehouseReceiptHeader: Record "Warehouse Receipt Header"; SalesLine: Record "Sales Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateShptLineFromSalesLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; SalesHeader: Record "Sales Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateShptLineFromPurchLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeCreateShptLineFromTransLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; TransferLine: Record "Transfer Line"; TransferHeader: Record "Transfer Header")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeWhseReceiptLineInsert(var WarehouseReceiptLine: Record "Warehouse Receipt Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeWhseShptLineInsert(var WarehouseShipmentLine: Record "Warehouse Shipment Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeUpdateRcptLineFromTransLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; TransferLine: Record "Transfer Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnSalesLine2ReceiptLineOnAfterInitNewLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; WhseReceiptHeader: Record "Warehouse Receipt Header"; SalesLine: Record "Sales Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFromServiceLine2ShptLineOnAfterInitNewLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header"; ServiceLine: Record "Service Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFromPurchLine2ShptLineOnAfterInitNewLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header"; PurchLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFromPurchLine2ShptLineOnBeforeCreateShptLine(var WarehouseShipmentLine: Record "Warehouse Shipment Line"; WarehouseShipmentHeader: Record "Warehouse Shipment Header"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnPurchLine2ReceiptLineOnAfterInitNewLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; WhseReceiptHeader: Record "Warehouse Receipt Header"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnPurchLine2ReceiptLineOnAfterSetQtysOnRcptLine(var WarehouseReceiptLine: Record "Warehouse Receipt Line"; PurchaseLine: Record "Purchase Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFromTransLine2ShptLineOnAfterInitNewLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header"; TransferLine: Record "Transfer Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnTransLine2ReceiptLineOnAfterInitNewLine(var WhseReceiptLine: Record "Warehouse Receipt Line"; WhseReceiptHeader: Record "Warehouse Receipt Header"; TransferLine: Record "Transfer Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnFromSalesLine2ShptLineOnBeforeCreateShipmentLine(WarehouseShipmentHeader: Record "Warehouse Shipment Header"; SalesLine: Record "Sales Line"; var TotalOutstandingWhseShptQty: Decimal; var TotalOutstandingWhseShptQtyBase: Decimal)
    begin
    end;

    [Scope('Internal')]
    procedure "+++FNK_INHAUS+++"()
    begin
    end;

    [Scope('Internal')]
    procedure ICNeu_FromSalesLine2ShptLine(PAR_RE_WhseShptHeader: Record "Warehouse Shipment Header"; PAR_RE_SalesLine: Record "Sales Line"; PAR_RE_SalesHeader: Record "Sales Header"): Boolean
    var
        Item: Record Item;
        WhseShptLine: Record "Warehouse Shipment Line";
        lo_re_ReserveEntryView: Record VIEW_ReservationEntry;
        lo_re_ReserveEntry: Record "Reservation Entry";
        lo_re_ReserveEntryForeign: Record "Reservation Entry";
        lo_cu_ItemMgt: Codeunit INHItemMgt;
        lo_cu_LogisticsMgt: Codeunit INHLogisticsMgt;
        lo_in_NextLineNo: Integer;
        WhseMgt: Codeunit "Whse. Management";
    begin
        //A19°
        PAR_RE_SalesLine.CalcFields("Whse. Outstanding Qty. (Base)");
        if PAR_RE_SalesLine."Outstanding Qty. (Base)" <= PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)" then
            exit;

        with WhseShptLine do begin
            Reset;

            if Item.Get(PAR_RE_SalesLine."No.") and (Item.Artikeltyp = Item.Artikeltyp::Set) then
                Artikeltyp := Artikeltyp::Set
            else
                Artikeltyp := PAR_RE_SalesLine.Artikeltyp;

            // Montageartikel dürfen nicht im Rüsttopf landen
            //START Axx°.1 ---------------------------------
            //IF Item.Artikeltyp = Item.Artikeltyp::Montage THEN
            //  EXIT;
            if (Item.Artikeltyp = Item.Artikeltyp::Montage) and not (lo_cu_ItemMgt.fnk_IsMontageLogisticExcptn(Item."No.")) then
                exit;
            //STOP Axx°.1 ----------------------------------

            "No." := PAR_RE_WhseShptHeader."No.";
            SetRange("No.", "No.");
            LockTable;
            if FindLast then;

            Init;
            "Line No." := "Line No." + 10000;
            "Source Type" := DATABASE::"Sales Line";
            "Source Subtype" := PAR_RE_SalesLine."Document Type";
            "Source No." := PAR_RE_SalesLine."Document No.";
            "Source Line No." := PAR_RE_SalesLine."Line No.";
            // (IC-Neu): Keine Anpassung des Funktionsaufrufs notwendig
            "Source Document" := WhseMgt.GetSourceDocument("Source Type", "Source Subtype");

            // TODO: Sauber machen
            "Location Code" := '1';

            "Item No." := PAR_RE_SalesLine."No.";
            "Variant Code" := PAR_RE_SalesLine."Variant Code";
            PAR_RE_SalesLine.TestField("Unit of Measure");
            "Unit of Measure Code" := PAR_RE_SalesLine."Unit of Measure Code";
            "Qty. per Unit of Measure" := PAR_RE_SalesLine."Qty. per Unit of Measure";
            Description := PAR_RE_SalesLine.Description;
            "Description 2" := PAR_RE_SalesLine."Description 2";

            // TODO: Das kalkulierte Feld "SalesLine.Qty. to Ship" ist nicht sauber! Hier müssen die Zeilen aus dem Logistiktopf kommen!
            "Qty. Outstanding" := PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)";
            "Qty. Outstanding (Base)" := PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)";
            if not lo_cu_LogisticsMgt.fnk_LocationIsDirectedPutAwayAndPick("Location Code") then begin   //C54°
                "Qty. to Ship" := PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)";
                "Qty. to Ship (Base)" := PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)";
            end;   //C54°
            Quantity := PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)";
            "Qty. (Base)" := (PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)")
                                     * "Qty. per Unit of Measure";
            "Completely Picked" := ((PAR_RE_SalesLine."Qty. to Ship" - PAR_RE_SalesLine."Whse. Outstanding Qty. (Base)") = "Qty. Picked")
                                    or ("Qty. (Base)" = "Qty. Picked (Base)");

            if PAR_RE_SalesLine."Document Type" = PAR_RE_SalesLine."Document Type"::Order then begin
                //START Axx°.2 ---------------------------------
                //"Due Date" := PAR_RE_SalesLine."Planned Shipment Date";
                "Due Date" := PAR_RE_SalesLine."Promised Delivery Date";
                //STOP  Axx°.2 ---------------------------------
            end;
            if PAR_RE_SalesLine."Document Type" = PAR_RE_SalesLine."Document Type"::"Return Order" then
                "Due Date" := WorkDate;

            "Shipment Date" := PAR_RE_SalesLine."Shipment Date";
            "Destination Type" := "Destination Type"::Customer;
            "Destination No." := PAR_RE_SalesLine."Sell-to Customer No.";
            "Shipping Advice" := PAR_RE_SalesHeader."Shipping Advice";
            "Installation Group" := PAR_RE_SalesLine."Installation Group";   //B74°

            "Shelf No." := lo_cu_ItemMgt.FNK_RegalnummerZuArtikel(PAR_RE_SalesLine."No.", WorkDate, PAR_RE_SalesLine."Location Code");
            "ZT Ausfuhr" := PAR_RE_SalesLine."ZT Ausfuhr";
            "Shipping Agent Code" := PAR_RE_SalesLine."Shipping Agent Code";
            IC_Company := PAR_RE_WhseShptHeader.IC_Company;

            WhseShptLine.GehörtZuZeilennr := PAR_RE_SalesLine."Attached to Line No.";
            if Item.Get("Item No.") and (Item.Artikeltyp = Item.Artikeltyp::Set) then
                WhseShptLine.Artikeltyp := WhseShptLine.Artikeltyp::Set
            else
                WhseShptLine.Artikeltyp := PAR_RE_SalesLine.Artikeltyp;

            ICNeu_UpdateShptLine(WhseShptLine, PAR_RE_WhseShptHeader);

            lo_re_ReserveEntryView.Reset;
            lo_re_ReserveEntryView.SetRange(Company, PAR_RE_SalesHeader.IC_Mandant);
            lo_re_ReserveEntryView.SetRange("Source Type", DATABASE::"Sales Line");
            lo_re_ReserveEntryView.SetRange("Source Subtype", 1);
            lo_re_ReserveEntryView.SetRange("Source ID", PAR_RE_SalesLine."Document No.");
            lo_re_ReserveEntryView.SetRange("Source Ref. No.", PAR_RE_SalesLine."Line No.");
            lo_re_ReserveEntryView.SetFilter("Reservation Status", '<>%1', lo_re_ReserveEntryView."Reservation Status"::Reservation);   //C03°
            if lo_re_ReserveEntryView.FindSet(false, false) then begin

                lo_re_ReserveEntry.Reset;
                lo_re_ReserveEntry.SetRange("Source Type", DATABASE::"Sales Line");
                lo_re_ReserveEntry.SetRange("Source Subtype", 1);
                lo_re_ReserveEntry.SetRange("Source ID", PAR_RE_SalesLine."Document No.");
                lo_re_ReserveEntry.SetRange("Source Ref. No.", PAR_RE_SalesLine."Line No.");
                lo_re_ReserveEntry.DeleteAll;
                lo_re_ReserveEntry.Reset;
                if lo_re_ReserveEntry.FindLast then
                    lo_in_NextLineNo := lo_re_ReserveEntry."Entry No." + 1
                else
                    lo_in_NextLineNo := 1;
                lo_re_ReserveEntry.Init;
                repeat
                    lo_re_ReserveEntry.TransferFields(lo_re_ReserveEntryView);
                    lo_re_ReserveEntry."Entry No." := lo_in_NextLineNo;
                    //START C54° ---------------------------------
                    lo_re_ReserveEntry."Transferred from Entry No." := 0;
                    lo_re_ReserveEntry."Item Ledger Entry No." := 0;
                    lo_re_ReserveEntry."Appl.-to Item Entry" := 0;
                    lo_re_ReserveEntry."Appl.-from Item Entry" := 0;
                    //STOP  C54° ---------------------------------
                    lo_re_ReserveEntry."Source Type" := DATABASE::"Sales Line";
                    lo_re_ReserveEntry."Source Subtype" := 1;
                    lo_re_ReserveEntry."Source ID" := PAR_RE_SalesLine."Document No.";
                    lo_re_ReserveEntry."Source Ref. No." := PAR_RE_SalesLine."Line No.";
                    lo_re_ReserveEntry."Location Code" := "Location Code";   //C54°
                    lo_re_ReserveEntry.Validate("Qty. to Handle (Base)", lo_re_ReserveEntryView."Quantity (Base)");

                    lo_re_ReserveEntry.Insert;

                    //START C54° ---------------------------------
                    //Lagerort in den Reservierungsposten berichtigen, kann durch einen Bug falsch sein
                    if lo_re_ReserveEntryView."Location Code" <> "Location Code" then begin
                        lo_re_ReserveEntryForeign.ChangeCompany(lo_re_ReserveEntryView.Company);
                        if lo_re_ReserveEntryForeign.Get(lo_re_ReserveEntryView."Entry No.", lo_re_ReserveEntryView.Positive) then begin
                            lo_re_ReserveEntryForeign."Location Code" := "Location Code";
                            lo_re_ReserveEntryForeign.Modify(false);
                        end;
                    end;
                    //STOP  C54° ---------------------------------

                    lo_in_NextLineNo := lo_in_NextLineNo + 1;
                until lo_re_ReserveEntryView.Next = 0;
            end;

            if ICNeu_CreateShptLine(WhseShptLine) then begin
                OnAfterCreateShptLineFromSalesLine(WhseShptLine, PAR_RE_WhseShptHeader, PAR_RE_SalesLine, PAR_RE_SalesHeader);  //C54°
                exit(true);
            end;
        end;
    end;

    local procedure ICNeu_CreateShptLine(var WhseShptLine: Record "Warehouse Shipment Line") Created: Boolean
    var
        Item: Record Item;
        Artikelverwaltung: Codeunit INHItemMgt;
    begin
        //A19°
        with WhseShptLine do begin
            Item."No." := "Item No.";
            Item.ItemSKUGet(Item, "Location Code", "Variant Code");

            "Shelf No." := Artikelverwaltung.FNK_RegalnummerZuArtikel(Item."No.", WorkDate, WhseShptLine."Location Code");

            if Insert then
                Created := true;
        end;
    end;

    local procedure ICNeu_UpdateShptLine(var WhseShptLine: Record "Warehouse Shipment Line"; WhseShptHeader: Record "Warehouse Shipment Header")
    begin
        //A19°
        with WhseShptLine do begin
            // Eigentlich werden VALIDATE Aufrufe hier verwendet, aber diese können an dieser Stelle als Zuweisungen ersetzt werden,
            // die Logik aus den VALIDATE Triggern ist nicht notwendig!
            "Zone Code" := WhseShptHeader."Zone Code";
            "Bin Code" := WhseShptHeader."Bin Code";
        end;
    end;
}

