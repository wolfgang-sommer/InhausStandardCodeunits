codeunit 50114 INHGenJnlPostPrint
{
    // +---------------------------------------------+
    // +                                             +
    // +           Inhaus Handels GmbH               +
    // +                                             +
    // +---------------------------------------------+
    // 
    // ID    Requ.   KZ   Datum     Beschreibung
    // ------------------------------------------------------------
    // Axx°.1        SSC  18.10.18  Standard BUG: "Gen. Jnl.-Post Batch" muss als Variable aufgerufen werden (war in 2009 schon so),
    //                               weil GenJnlLine."Line No." geändert wird und zurückgegeben werden muss, damit das richtige gedruckt wird (siehe auch Cu13)
    //               SSC  22.10.18  Über eigene Funktion lösen; führt sonst anderswo zu Problemen

    TableNo = "Gen. Journal Line";

    trigger OnRun()
    begin
        GenJnlLine.Copy(Rec);
        Code;
        // Copy(GenJnlLine);
    end;

    var
        Text000: Label 'cannot be filtered when posting recurring journals';
        Text001: Label 'Do you want to post the journal lines and print the report(s)?';
        Text002: Label 'There is nothing to post.';
        Text003: Label 'The journal lines were successfully posted.';
        Text004: Label 'The journal lines were successfully posted. You are now in the %1 journal.';
        GenJnlTemplate: Record "Gen. Journal Template";
        GenJnlLine: Record "Gen. Journal Line";
        GLReg: Record "G/L Register";
        CustLedgEntry: Record "Cust. Ledger Entry";
        VendLedgEntry: Record "Vendor Ledger Entry";
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
        TempJnlBatchName: Code[10];

    local procedure "Code"()
    var
        ConfirmManagement: Codeunit "Confirm Management";
        HideDialog: Boolean;
        IsHandled: Boolean;
    begin
        HideDialog := false;
        with GenJnlLine do begin
            GenJnlTemplate.Get("Journal Template Name");
            if GenJnlTemplate."Force Posting Report" or
               (GenJnlTemplate."Cust. Receipt Report ID" = 0) and (GenJnlTemplate."Vendor Receipt Report ID" = 0)
            then
                GenJnlTemplate.TestField("Posting Report ID");
            if GenJnlTemplate.Recurring and (GetFilter("Posting Date") <> '') then
                FieldError("Posting Date", Text000);

            OnBeforePostJournalBatch(GenJnlLine, HideDialog);

            if not HideDialog then
                if not ConfirmManagement.GetResponse(Text001, true) then
                    exit;

            TempJnlBatchName := "Journal Batch Name";

            //START Axx°.1 ---------------------------------
            //  CODEUNIT.RUN(CODEUNIT::"Gen. Jnl.-Post Batch",GenJnlLine);
            GenJnlPostBatch.Run(GenJnlLine);
            //STOP  Axx°.1 ---------------------------------

            OnAfterPostJournalBatch(GenJnlLine);

            //START Axx°.1 ---------------------------------
            IF GLReg.GET("Line No.") THEN BEGIN

                // if GLReg.Get(GenJnlPostBatch.GetGLRegNo) then begin
                //STOP  Axx°.1 ---------------------------------
                if GenJnlTemplate."Cust. Receipt Report ID" <> 0 then begin
                    CustLedgEntry.SetRange("Entry No.", GLReg."From Entry No.", GLReg."To Entry No.");
                    REPORT.Run(GenJnlTemplate."Cust. Receipt Report ID", false, false, CustLedgEntry);
                end;
                if GenJnlTemplate."Vendor Receipt Report ID" <> 0 then begin
                    VendLedgEntry.SetRange("Entry No.", GLReg."From Entry No.", GLReg."To Entry No.");
                    REPORT.Run(GenJnlTemplate."Vendor Receipt Report ID", false, false, VendLedgEntry);
                end;
                if GenJnlTemplate."Posting Report ID" <> 0 then begin
                    GLReg.SetRecFilter;
                    OnBeforeGLRegPostingReportPrint(GenJnlTemplate."Posting Report ID", false, false, GLReg, IsHandled);
                    if not IsHandled then
                        REPORT.Run(GenJnlTemplate."Posting Report ID", false, false, GLReg);
                end;
            end;

            if not HideDialog then
                if "Line No." = 0 then
                    Message(Text002)
                else
                    if TempJnlBatchName = "Journal Batch Name" then
                        Message(Text003)
                    else
                        Message(Text004, "Journal Batch Name");

            if not Find('=><') or (TempJnlBatchName <> "Journal Batch Name") then begin
                Reset;
                FilterGroup(2);
                SetRange("Journal Template Name", "Journal Template Name");
                SetRange("Journal Batch Name", "Journal Batch Name");
                OnGenJnlLineSetFilter(GenJnlLine);
                FilterGroup(0);
                "Line No." := 1;
            end;
        end;
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterPostJournalBatch(var GenJournalLine: Record "Gen. Journal Line")
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeGLRegPostingReportPrint(var ReportID: Integer; ReqWindow: Boolean; SystemPrinter: Boolean; var GLRegister: Record "G/L Register"; var Handled: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforePostJournalBatch(var GenJournalLine: Record "Gen. Journal Line"; var HideDialog: Boolean)
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnGenJnlLineSetFilter(var GenJournalLine: Record "Gen. Journal Line")
    begin
    end;
}

