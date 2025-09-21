codeunit 50158 INHWhsePostShipmentYesNo
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
    // C27°          SSC  15.12.17  Hooks

    TableNo = "Warehouse Shipment Line";

    trigger OnRun()
    begin
        WhseShptLine.Copy(Rec);
        Code;
        Rec := WhseShptLine;
    end;

    var
        WhseShptLine: Record "Warehouse Shipment Line";
        WhsePostShipment: Codeunit "Whse.-Post Shipment";
        Selection: Integer;
        ShipInvoiceQst: Label '&Ship,Ship &and Invoice';

    local procedure "Code"()
    var
        Invoice: Boolean;
        HideDialog: Boolean;
        IsPosted: Boolean;
        "+++LO_VAR_INHAUS+++": Boolean;
        lo_cu_LogisticsMgt: Codeunit INHLogisticsMgt;
    begin
        HideDialog := false;
        IsPosted := false;
        OnBeforeConfirmWhseShipmentPost(WhseShptLine, HideDialog, Invoice, IsPosted);
        if IsPosted then
            exit;

        with WhseShptLine do begin
            if Find then
                if not HideDialog then begin
                    //START A08° ---------------------------------
                    //      Selection := STRMENU(ShipInvoiceQst,1);
                    //      IF Selection = 0 THEN
                    //        EXIT;
                    //      Invoice := (Selection = 2);
                    Invoice := false;
                    Selection := 1;
                    //STOP  A08° ---------------------------------
                end;

            OnAfterConfirmPost(WhseShptLine, Invoice);

            WhsePostShipment.SetPostingSettings(Invoice);
            WhsePostShipment.SetPrint(false);
            WhsePostShipment.Run(WhseShptLine);
            //A08°:WhsePostShipment.GetResultMessage;
            Clear(WhsePostShipment);
        end;

        // lo_cu_LogisticsMgt.fnk_Cu5764_OnAfterCode(WhseShptLine);   //C27°
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterConfirmPost(WhseShipmentLine: Record "Warehouse Shipment Line"; Invoice: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeConfirmWhseShipmentPost(var WhseShptLine: Record "Warehouse Shipment Line"; var HideDialog: Boolean; var Invoice: Boolean; var IsPosted: Boolean)
    begin
    end;
}

